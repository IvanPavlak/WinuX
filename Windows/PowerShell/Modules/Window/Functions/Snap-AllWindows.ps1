function Snap-AllWindows {
	<#
	.SYNOPSIS
		Snaps positioned windows into their FancyZones zones, desktop by desktop.
	.DESCRIPTION
		Places the windows tracked by Set-WindowLayouts into their zones by:
		- Grouping windows by virtual desktop and switching desktops as needed
		- Sending Win+Up for multi-zone layouts (the window arrives pre-inset inside its
		  target zone, so FancyZones' relative move resolves to that zone), with a
		  shift-drag fallback when the keyboard snap does not verify
		- Snapping single-zone layouts (Zone = "Fullscreen"/"Full" on a one-zone grid)
		  through Invoke-SingleZoneWindowSnap so those windows end up REGISTERED with
		  FancyZones, not merely positioned: a stale zone assignment is cleared first (it
		  makes Win+Up a no-op or a cross-monitor throw on a one-zone grid), the window is
		  centered in the zone at a deeper inset, then Win+Up with a shift-drag fallback
		- Using reliable focus acquisition with thread attachment for every keyboard snap

		A window whose snap attempts are exhausted is recorded as failed and the pass
		CONTINUES with the remaining windows and desktops, so one stubborn window no longer
		strands every later desktop at its inset size. A circuit breaker aborts the pass
		once several windows have failed - that pattern means something systemic (stuck
		modifier, wedged FancyZones) that the caller's retry must reset first. After the
		desktop loop, a verification sweep re-checks that every tracked window is still on
		its assigned desktop and retries stragglers once: the upstream Move-Window falls
		back to moving a process's MAIN window when the requested view cannot be moved, so
		positioning a later sibling of a multi-window process can silently displace an
		already-snapped window.

		When using -All switch, snaps all visible windows without requiring prior positioning.
		In workspace mode, failed keyboard/shift-drag snap retries are returned to
		Set-WorkspaceWindowLayout so the workspace command can be rerun.

		After processing all desktops, the active desktop is left on the last one snapped.
		This function no longer switches back to the first desktop - returning the user there
		is delegated to Focus-VirtualDesktop (the final workspace action) so the
		switch-and-focus logic lives in one place (DRY).
	.PARAMETER All
		Snaps all visible windows without requiring prior positioning by Set-WindowLayouts.
		Useful for standalone usage without the workspace flow.
	.PARAMETER CurrentDesktopOnly
		Only valid with -All. Restricts snapping to windows that live on the currently
		active virtual desktop. GetAllWindows() (EnumWindows) returns windows across ALL
		virtual desktops, so callers that switch desktops in a loop must set this to avoid
		re-snapping every window on every pass and to keep focus from being dragged to a
		window that lives on another desktop.

	.PARAMETER WindowHandles
		Only valid with -All. Restricts snapping to exactly these window handles and takes
		precedence over -CurrentDesktopOnly. Callers that already resolved the
		window-to-desktop mapping (e.g. the simple-layout loop) pass the per-desktop handle
		list here instead of paying two COM roundtrips per window on every desktop pass.
	.PARAMETER SnapDelayMs
		Delay in milliseconds between each window snap in -All mode. Default is 25ms.
		The positioned-window path (workspace flow) verifies every snap and placement with
		Wait-WindowRect instead of fixed delays, so this parameter has no effect there.
	.PARAMETER DesktopOffset
		Virtual desktop offset, so alongside workspaces target the correct desktop. Default is 0.
	.PARAMETER DesktopCount
		Number of desktops to process. Default is 0.
	.EXAMPLE
		Snap-AllWindows
		# Snaps positioned windows to FancyZones (workspace flow)
	.EXAMPLE
		Snap-AllWindows -All
		# Snaps all visible windows to FancyZones (standalone usage)
	.EXAMPLE
		Snap-AllWindows -All -SnapDelayMs 100
	.NOTES
		Be sure to disable "Move newly created windows to their last known zone"
		This will ensure windows aren't moved to the wrong position with this function
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[switch]$All,

		[Parameter()]
		[switch]$CurrentDesktopOnly,

		# Only valid with -All: restrict snapping to exactly these window handles. Callers
		# that already know the window->desktop mapping (e.g. the simple-layout loop) pass
		# the per-desktop handle list here instead of paying -CurrentDesktopOnly's two COM
		# roundtrips per window on every desktop pass.
		[Parameter()]
		[IntPtr[]]$WindowHandles,

		[Parameter()]
		[int]$SnapDelayMs = 25,

		[Parameter()]
		[int]$DesktopOffset = 0,

		[Parameter()]
		[int]$DesktopCount = 0
	)

	begin {
		# Ensure Windows Forms is loaded (cached) for monitor info
		Ensure-WindowsFormsLoaded

		$fancyZonesReady = Start-FancyZones -PassThru
		if (-not $fancyZonesReady) {
			$fancyZonesReady = Start-FancyZones -ForceRestart -MaxWaitSeconds 20 -PassThru
		}

		if (-not $fancyZonesReady) {
			throw "FancyZones is not ready after restart attempt."
		}
	}

	process {
		$script:LastSnapAllWindowsResult = [PSCustomObject]@{
			SnappedCount  = 0
			FailedWindows = @()
		}

		# -All mode: snap all visible windows without requiring prior positioning
		if ($All) {
			Write-LogDebug "[Snapping All Visible Windows to FancyZones]"

			# Start from a clean keyboard state: a modifier left logically stuck by an
			# earlier interrupted sequence corrupts every combo sent below (a held Shift
			# turns Win+Up into Win+Shift+Up) and locks up terminal input session-wide.
			$null = Reset-KeyboardModifiers

			$allWindows = [WindowModule.Native]::GetAllWindows()

			# Explicit handle list wins: the caller already resolved which windows belong to
			# the active desktop, so no per-window COM filtering is needed.
			if ($WindowHandles -and $WindowHandles.Count -gt 0) {
				$handleFilter = [System.Collections.Generic.HashSet[IntPtr]]::new()
				foreach ($requestedHandle in $WindowHandles) {
					[void]$handleFilter.Add($requestedHandle)
				}
				$allWindows = @($allWindows | Where-Object { $handleFilter.Contains($_.Handle) })

				Write-LogDebug "  Restricting to [$($allWindows.Count)] caller-specified window(s)"
			}
			# GetAllWindows() (EnumWindows) returns windows across ALL virtual desktops.
			# When -CurrentDesktopOnly is set, keep only windows on the active desktop so a
			# desktop-switching caller snaps each window exactly once on its own desktop and
			# never pulls focus to a window that lives elsewhere.
			elseif ($CurrentDesktopOnly) {
				$currentDesktopIndex = $null
				try {
					$currentDesktopIndex = Get-DesktopIndex (Get-CurrentDesktop)
				}
				catch {
					$currentDesktopIndex = $null
				}

				if ($null -ne $currentDesktopIndex) {
					$allWindows = @($allWindows | Where-Object {
							try {
								(Get-DesktopIndex (Get-DesktopFromWindow -Hwnd $_.Handle.ToInt64())) -eq $currentDesktopIndex
							}
							catch {
								# Unresolvable desktop (e.g. pinned/system window) - snap it rather than drop it.
								$true
							}
						})

					Write-LogDebug "  Restricting to [$($allWindows.Count)] window(s) on current desktop [$($currentDesktopIndex + 1)]"
				}
				elseif (Test-LogVerbose) {
					Write-LogDebug "  ⚠ Could not resolve current desktop - snapping all visible windows" -Style Warning
				}
			}

			$snappedCount = 0

			foreach ($window in $allWindows) {
				$handle = $window.Handle
				$title = $window.Title

				# Skip system windows
				if ($title -match '^(Program Manager|Windows Input Experience|TextInputHost|Search|Start|Action center)$') {
					continue
				}

				try {
					[void][WindowModule.Native]::ForceForegroundWindow($handle)
					Start-Sleep -Milliseconds $script:WindowModuleDelays.FocusSettleMs

					# Send Win+Up to snap to FancyZones using batched SendInput
					[WindowModule.Native]::SendSnapKey($true)

					Start-Sleep -Milliseconds $SnapDelayMs

					Write-LogDebug "     ✓ Snapped [$title]" -Style Success
					$snappedCount++
				}
				catch {
					if (Test-LogVerbose) {
						Write-Warning "`n  ✗ Failed to snap [$title] => $_"
					}
				}
			}

			Write-LogDebug "=> Snapped [$snappedCount] window(s) to FancyZones!" -Style Success

			$script:LastSnapAllWindowsResult = [PSCustomObject]@{
				SnappedCount  = $snappedCount
				FailedWindows = @()
			}

			return
		}

		# Positioned windows mode (workspace flow)
		$positionedCount = Get-PositionedWindowCount
		if ($positionedCount -eq 0) {
			Write-LogDebug " No windows were positioned by Set-WindowLayouts!" -Style Warning
			return
		}

		# Monitor snapshots are refreshed per desktop to avoid stale geometry/state.
		$monitors = @()

		Write-LogDebug "[Snapping Windows to FancyZones]"

		# Start from a clean keyboard state: a modifier left logically stuck by an
		# earlier interrupted sequence corrupts every combo sent below (a held Shift
		# turns Win+Up into Win+Shift+Up) and locks up terminal input session-wide.
		$null = Reset-KeyboardModifiers

		$snappedCount = 0
		$failedSnaps = [System.Collections.Generic.List[object]]::new()
		# A window that exhausts its attempts is recorded in $failedSnaps and the pass moves
		# on - the caller's retry re-runs the full layout for the stragglers. $snapAborted is
		# reserved for the two cases where continuing is pointless: FancyZones died, or the
		# circuit breaker below tripped because this many windows failed in one pass -
		# individual apps fail individually; a cluster means something systemic (stuck
		# modifier, wedged FancyZones grid) that burns 3 attempts + shift-drag for EVERY
		# remaining window unless the pass is handed back to the caller's reset-and-retry.
		$maxFailedWindows = 3
		$snapAborted = $false

		# Process windows in the order they were positioned (Desktop 1 Monitor 1, Desktop 1 Monitor 2, etc.)
		if (-not $script:PositionedWindowHandles) {
			Write-LogDebug " Positioned window tracking not initialized!" -Style Warning
			$script:LastSnapAllWindowsResult = [PSCustomObject]@{
				SnappedCount  = 0
				FailedWindows = @()
			}
			return
		}

		# Group windows by desktop number for efficient desktop switching
		# DesktopNumber is 1-based in layout files, convert to 0-based for internal use
		$windowsByDesktop = @{}
		foreach ($windowState in $script:PositionedWindowHandles) {
			$desktopNum = if ($null -ne $windowState.DesktopNumber) { $windowState.DesktopNumber } else { 1 }
			if (-not $windowsByDesktop.ContainsKey($desktopNum)) {
				$windowsByDesktop[$desktopNum] = [System.Collections.Generic.List[object]]::new()
			}
			$windowsByDesktop[$desktopNum].Add($windowState)
		}

		# Sort desktop numbers for consistent processing
		$sortedDesktops = $windowsByDesktop.Keys | Sort-Object

		# Calculate inset values with the same helper used by Set-WindowLayouts, from the same
		# single source of truth (SnapInsetPercent in configuration)
		$insetPercent = Get-WindowInsetPercent

		# Re-check FancyZones liveness during long-running multi-desktop loops.
		$ensureFancyZonesRunning = {
			$runningFancyZones = Get-Process -Name "PowerToys.FancyZones" -ErrorAction SilentlyContinue
			if ($runningFancyZones) {
				return $true
			}

			Write-LogDebug "  ⚠ FancyZones process is not running, attempting restart..." -Style Warning

			$restartReady = Start-FancyZones -ForceRestart -MaxWaitSeconds 20 -PassThru
			return [bool]$restartReady
		}

		foreach ($desktopNum in $sortedDesktops) {
			# Convert 1-based DesktopNumber to 0-based for VirtualDesktop module,
			# applying DesktopOffset so alongside workspaces target the correct desktop.
			$internalDesktopIndex = ConvertTo-InternalDesktopIndex -DesktopNumber $desktopNum -DesktopOffset $DesktopOffset

			# Switch to the target desktop
			if (Test-LogVerbose) {
				Write-LogDebug " Switching to Desktop [$desktopNum]..."
			}

			$desktopSwitched = $false
			$maxDesktopSwitchRetries = 3
			for ($desktopSwitchAttempt = 1; $desktopSwitchAttempt -le $maxDesktopSwitchRetries; $desktopSwitchAttempt++) {
				try {
					$null = Switch-Desktop -Desktop $internalDesktopIndex -ErrorAction Stop
					if (Wait-DesktopSwitch -TargetDesktopIndex $internalDesktopIndex) {
						$desktopSwitched = $true
						break
					}
				}
				catch {
					Write-LogDebug "  ⚠ Failed to switch to desktop $desktopNum (attempt $desktopSwitchAttempt/$maxDesktopSwitchRetries): $_" -Style Warning
				}
			}

			if (-not $desktopSwitched) {
				$moduleReloaded = Reset-VirtualDesktopState
				if ($moduleReloaded) {
					try {
						$null = Switch-Desktop -Desktop $internalDesktopIndex -ErrorAction Stop
						$desktopSwitched = Wait-DesktopSwitch -TargetDesktopIndex $internalDesktopIndex
					}
					catch {
						$desktopSwitched = $false
					}
				}

				if (Test-LogVerbose) {
					if ($desktopSwitched) {
						Write-LogDebug "  ⚠ Desktop [$desktopNum] recovered after VirtualDesktop module reset" -Style Warning
					}
					else {
						Write-LogDebug "  ✗ Aborting desktop [$desktopNum] - unable to switch after retries" -Style Error
					}
				}

				if (-not $desktopSwitched) {
					continue
				}
			}

			# Refresh cached state after desktop transitions to avoid stale handle/process snapshots.
			Clear-WindowCache
			Clear-MonitorCache
			$monitors = Get-CachedMonitors

			# FancyZones liveness is re-checked once per DESKTOP pass (it used to run per
			# WINDOW - one Get-Process each, ~0.3s across a 10-window workspace).
			if (-not (& $ensureFancyZonesRunning)) {
				$failedSnaps.Add([PSCustomObject]@{
						Handle      = [IntPtr]::Zero
						WindowTitle = "Desktop $desktopNum"
						ProcessName = $null
						Expected    = $null
						Actual      = $null
						Error       = "FancyZones became unavailable before snapping desktop [$desktopNum]"
					})
				$snapAborted = $true
				break
			}

			# Surface a stale/missing FancyZones layout for this desktop so blind snapping
			# into a wrong or unapplied zone grid is at least diagnosable.
			if (Test-LogVerbose) {
				$desktopGuid = Get-VirtualDesktopGuid -DesktopIndex $internalDesktopIndex
				if ($desktopGuid -and -not (Test-FancyZonesLayoutApplied -VirtualDesktopGuid $desktopGuid)) {
					Write-LogDebug "  ⚠ No FancyZones layout detected for desktop [$desktopNum] - snapping may be unreliable" -Style Warning
				}
			}

			foreach ($windowState in $windowsByDesktop[$desktopNum]) {
				$handle = $windowState.Handle
				$expectedX = $windowState.ExpectedX
				$expectedY = $windowState.ExpectedY
				$expectedWidth = $windowState.ExpectedWidth
				$expectedHeight = $windowState.ExpectedHeight
				$expectedTitle = $windowState.WindowTitle
				$expectedProcessId = [uint32]($windowState.ProcessId)

				# Calculate the adjusted inset bounds using the shared resize helper.
				$resizeBounds = Get-InsetWindowBounds -TargetX $expectedX -TargetY $expectedY -TargetWidth $expectedWidth -TargetHeight $expectedHeight -InsetPercent $insetPercent
				$adjustedX = $resizeBounds.AdjustedX
				$adjustedY = $resizeBounds.AdjustedY
				$adjustedWidth = $resizeBounds.AdjustedWidth
				$adjustedHeight = $resizeBounds.AdjustedHeight

				# Pre-snap validation: verify handle and process fingerprint are still valid.
				$windowSignatureValid = $true
				$currentProcessId = [uint32]0
				try {
					[void][WindowModule.Native]::GetWindowThreadProcessId($handle, [ref]$currentProcessId)
				}
				catch {
					$windowSignatureValid = $false
				}

				if ($windowSignatureValid -and $expectedProcessId -gt 0 -and $currentProcessId -ne $expectedProcessId) {
					$windowSignatureValid = $false
					Write-LogDebug "  ⚠ Process fingerprint changed for [$expectedTitle] (expected PID: $expectedProcessId, current PID: $currentProcessId)" -Style Warning
				}

				if (-not $windowSignatureValid) {
					$freshWindow = Resolve-PositionedWindowHandle -WindowState $windowState
					if ($freshWindow -and $freshWindow.Handle -ne [IntPtr]::Zero) {
						$handle = $freshWindow.Handle
						$windowState.Handle = $handle
						if ($freshWindow.ProcessId) {
							$windowState.ProcessId = [uint32]$freshWindow.ProcessId
						}
					}
					else {
						Write-LogDebug "  ✗ Skipping [$expectedTitle] - stale window handle could not be refreshed" -Style Error
						continue
					}
				}

				# Verify window rectangle and attempt stale-handle recovery when needed.
				$rect = New-Object WindowModule.RECT
				if (-not [WindowModule.Native]::GetWindowRect($handle, [ref]$rect)) {
					$replacementWindow = Resolve-PositionedWindowHandle -WindowState $windowState

					if ($replacementWindow -and $replacementWindow.Handle -ne [IntPtr]::Zero) {
						$handle = $replacementWindow.Handle
						$windowState.Handle = $handle
						if ($replacementWindow.ProcessId) {
							$windowState.ProcessId = [uint32]$replacementWindow.ProcessId
						}
						if ($replacementWindow.ProcessName) {
							$windowState.ProcessName = $replacementWindow.ProcessName
						}
						$rect = New-Object WindowModule.RECT
					}

					if (-not [WindowModule.Native]::GetWindowRect($handle, [ref]$rect)) {
						Write-LogDebug "  ✗ Skipping [$expectedTitle] - window handle no longer valid" -Style Error
						continue
					}
				}

				# Ensure window is still assigned to the desktop being processed.
				$windowOnTargetDesktop = $true
				try {
					$currentDesktop = Get-DesktopFromWindow -Hwnd $handle.ToInt64()
					$currentDesktopIndex = Get-DesktopIndex $currentDesktop
					if ($currentDesktopIndex -ne $internalDesktopIndex) {
						$windowOnTargetDesktop = $false
						$maxMoveRetries = 3
						for ($moveAttempt = 1; $moveAttempt -le $maxMoveRetries; $moveAttempt++) {
							# Move-WindowToVirtualDesktop verifies internally (immediate check +
							# short poll) - $true already means the window is on the target desktop.
							if (Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber $internalDesktopIndex) {
								$windowOnTargetDesktop = $true
								break
							}
						}
					}
				}
				catch {
					$windowOnTargetDesktop = $false
				}

				if (-not $windowOnTargetDesktop) {
					Write-LogDebug "  ⚠ Skipping [$expectedTitle] - could not align window to desktop [$desktopNum]" -Style Warning
					continue
				}

				# Single-zone layouts (Zone = "Fullscreen"/"Full" on a one-zone grid) snap through
				# FancyZones' own paths - centered in the zone at a deeper inset, Win+Up,
				# shift-drag fallback - so the window ends up REGISTERED (zone assignment,
				# live work-area tracking), not merely positioned. Win+Up is deterministic
				# because Invoke-SingleZoneWindowSnap clears a stale assignment first:
				# FancyZones' position-based move excludes zones the window is already
				# assigned to, which is what used to make single-zone Win+Up a no-op or a
				# cross-monitor throw (the marker survives every programmatic move, so
				# Reset-Windows leaves it behind routinely). An exhausted window is recorded
				# as failed for the caller's retry, exactly like the multi-zone path.
				if ($windowState.SingleZone) {
					$snap = Invoke-SingleZoneWindowSnap -WindowHandle $handle `
						-TargetX $expectedX -TargetY $expectedY `
						-TargetWidth $expectedWidth -TargetHeight $expectedHeight `
						-WindowTitle $expectedTitle -InsetPercent $insetPercent

					if ($snap.Verified) {
						$snappedCount++
						if (-not $snap.Registered) {
							Write-LogWarning "[$expectedTitle] is at its zone but its FancyZones assignment could not be read back - a manual Win+Arrow on it will re-register it"
						}
						elseif (Test-LogVerbose) {
							$methodLabel = switch ($snap.Method) {
								'KeyboardSnap' { 'Win+Up' }
								'ShiftDrag' { 'Shift+Drag' }
								default { $snap.Method }
							}
							$attemptLabel = if ($snap.Attempts -gt 1) { " (attempt $($snap.Attempts))" } else { "" }
							Write-LogDebug "     ✓ Snapped [$expectedTitle] → $methodLabel (registered, verified at zone position)$attemptLabel" -Style Success
						}
					}
					else {
						$errorDetails = "Single-zone snap FAILED for [$expectedTitle] after $($snap.Attempts) attempts (unverified position)"
						$actualBounds = $null
						if ($null -ne $snap.X) {
							$errorDetails += "`n  Expected => ($expectedX, $expectedY) ${expectedWidth}x${expectedHeight}"
							$errorDetails += "`n  Actual   => ($($snap.X), $($snap.Y)) $($snap.Width)x$($snap.Height)"
							$actualBounds = "($($snap.X), $($snap.Y)) $($snap.Width)x$($snap.Height)"
						}
						$failedSnaps.Add([PSCustomObject]@{
								Handle      = $handle
								WindowTitle = $expectedTitle
								ProcessName = $windowState.ProcessName
								Expected    = "($expectedX, $expectedY) ${expectedWidth}x${expectedHeight}"
								Actual      = $actualBounds
								Error       = $errorDetails
							})
						Write-LogDebug "     ✗ $errorDetails" -Style Error

						if ($failedSnaps.Count -ge $maxFailedWindows) {
							Write-LogDebug "     ✗ [$($failedSnaps.Count)] window(s) failed this pass - aborting (systemic failure, caller resets and retries)" -Style Error
							$snapAborted = $true
							break
						}
					}

					continue
				}

				$currentX = $rect.Left
				$currentY = $rect.Top
				$currentWidth = $rect.Right - $rect.Left
				$currentHeight = $rect.Bottom - $rect.Top

				# Validate window position against the ADJUSTED position (not full zone)
				$validationTolerance = $script:WindowModuleTolerances.PreSnapValidationPx
				$xValid = [Math]::Abs($currentX - $adjustedX) -le $validationTolerance
				$yValid = [Math]::Abs($currentY - $adjustedY) -le $validationTolerance
				# Dimensions may differ due to app constraints, so be more lenient
				$widthValid = [Math]::Abs($currentWidth - $adjustedWidth) -le ($validationTolerance * 2)
				$heightValid = [Math]::Abs($currentHeight - $adjustedHeight) -le ($validationTolerance * 2)

				# Position is critical for zone detection, dimensions less so
				if (-not ($xValid -and $yValid)) {
					if (Test-LogVerbose) {
						Write-LogDebug "  ⚠ Window [$expectedTitle] moved after positioning, attempting to re-position..." -Style Warning
						Write-LogDebug "    Expected (adjusted) => ($adjustedX, $adjustedY) ${adjustedWidth}x${adjustedHeight}"
						Write-LogDebug "    Actual => ($currentX, $currentY) ${currentWidth}x${currentHeight}"
						if (-not $widthValid -or -not $heightValid) {
							Write-LogDebug "    Note: Dimensions also differ (app may enforce size constraints)"
						}
					}

					# Attempt to re-position window on the fly using the shared resize path.
					$repositionSuccess = $false
					try {
						$null = Resize-Windows `
							-WindowHandle $handle `
							-TargetX $expectedX `
							-TargetY $expectedY `
							-TargetWidth $expectedWidth `
							-TargetHeight $expectedHeight `
							-InsetPercent $insetPercent
						$repositionResult = $script:LastResizeWindowsResult

						if ($repositionResult -and $repositionResult.ResizedCount -gt 0) {
							Start-Sleep -Milliseconds 10

							# Verify reposition worked
							$verifyRect = New-Object WindowModule.RECT
							if ([WindowModule.Native]::GetWindowRect($handle, [ref]$verifyRect)) {
								$verifyX = $verifyRect.Left
								$verifyY = $verifyRect.Top
								$verifyXValid = [Math]::Abs($verifyX - $adjustedX) -le $validationTolerance
								$verifyYValid = [Math]::Abs($verifyY - $adjustedY) -le $validationTolerance

								if ($verifyXValid -and $verifyYValid) {
									$repositionSuccess = $true
									Write-LogDebug "     ✓ Re-positioning successful, proceeding with snap" -Style Success

									# Update rect for direction calculation
									$rect = $verifyRect
								}
							}
						}
					}
					catch {
						Write-LogDebug "    ✗ Re-positioning failed: $_" -Style Error
					}

					if (-not $repositionSuccess) {
						Write-LogDebug "    ✗ Skipping snap for [$expectedTitle] - unable to restore expected position" -Style Error
						continue
					}
				}

				# Get window title
				$length = [WindowModule.Native]::GetWindowTextLength($handle)
				if ($length -eq 0) {
					continue
				}
				$sb = New-Object System.Text.StringBuilder ($length + 1)
				[void][WindowModule.Native]::GetWindowText($handle, $sb, $sb.Capacity)
				$title = $sb.ToString()

				# Calculate window dimensions
				$windowCenterX = ($rect.Left + $rect.Right) / 2
				$windowCenterY = ($rect.Top + $rect.Bottom) / 2

				# Find which monitor this window is on
				$windowMonitor = $null
				foreach ($monitor in $monitors) {
					$monitorBounds = $monitor.Bounds
					if ($windowCenterX -ge $monitorBounds.Left -and $windowCenterX -le $monitorBounds.Right -and
						$windowCenterY -ge $monitorBounds.Top -and $windowCenterY -le $monitorBounds.Bottom) {
						$windowMonitor = $monitor
						break
					}
				}

				if (-not $windowMonitor) {
					Write-LogDebug "  ⚠ Could not determine monitor for [$title]" -Style Warning
					continue
				}

				# Win+Up for every window (true = up, false = down for SendSnapKey).
				# The window arrives here already inset INSIDE its target zone, and the two
				# arrow directions are NOT symmetric for that state: Win+Up snaps the window
				# into the zone it is sitting in, while Win+Down hands it to the zone BELOW.
				# A "top half of a vertically split monitor" special case used to send
				# Win+Down for exactly those windows, so every top-half zone (Seven's
				# Top-Right, Four's top row, ...) landed one zone too low, failed
				# verification, and had to be recovered by the slow shift-drag fallback.
				$direction = "Up"
				$snapUp = $true

				# Snap the window with retry logic
				# FancyZones can miss keyboard/shift-drag snaps due to focus timing, event processing lag,
				# or input injection races. Retry with increasing delays to give FancyZones time to respond.
				$maxSnapRetries = 3
				$snapVerified = $false

				for ($snapAttempt = 1; $snapAttempt -le $maxSnapRetries; $snapAttempt++) {
					if ($snapVerified) { break }

					# Focus settle grows on retries; snap verification itself polls (Wait-WindowRect)
					# with a budget that also grows per attempt, replacing the old fixed delays.
					$focusSettleMs = 10 + (($snapAttempt - 1) * 40)

					if ($snapAttempt -gt 1) {
						Write-LogDebug "     ↻ Retry $snapAttempt/$maxSnapRetries for [$title]..."

						# The failed attempt itself may have stranded a modifier (or the
						# attempt failed BECAUSE one was already stuck and corrupted the
						# combo). Clear the keyboard state before injecting again so the
						# retry starts from a known-good baseline.
						$null = Reset-KeyboardModifiers

						# Re-position window before retrying (it may have been left in a bad state)
						try {
							$null = Resize-Windows `
								-WindowHandle $handle `
								-TargetX $expectedX `
								-TargetY $expectedY `
								-TargetWidth $expectedWidth `
								-TargetHeight $expectedHeight `
								-InsetPercent $insetPercent
							Start-Sleep -Milliseconds 20
						}
						catch {
							# Continue anyway
						}
					}

					try {
						# Acquire stable foreground focus immediately before injecting snap hotkeys.
						$focusAcquired = Confirm-WindowForeground -WindowHandle $handle -BaseSettleMs $focusSettleMs

						if (-not $focusAcquired) {
							Write-LogDebug "  ⚠ Could not acquire stable focus for [$title] (attempt $snapAttempt/$maxSnapRetries)" -Style Warning
							continue
						}

						# Re-check foreground atomically right before sending input.
						if ([WindowModule.Native]::GetForegroundWindow() -ne $handle) {
							[void][WindowModule.Native]::ForceForegroundWindow($handle)
							if ([WindowModule.Native]::GetForegroundWindow() -ne $handle) {
								Write-LogDebug "  ⚠ Foreground changed before snap key injection for [$title]" -Style Warning
								continue
							}
						}

						# Send Win + Arrow (UP or DOWN) using batched SendInput
						[WindowModule.Native]::SendSnapKey($snapUp)

						# Poll until FancyZones moves the window to the FULL zone position (not inset)
						# instead of a single fixed-delay check: returns as soon as the snap lands and
						# only escalates to the expensive shift-drag fallback when the budget is
						# genuinely exhausted (budget grows on retries).
						$snapWait = Wait-WindowRect -WindowHandle $handle `
							-ExpectedX $expectedX -ExpectedY $expectedY `
							-ExpectedWidth $expectedWidth -ExpectedHeight $expectedHeight `
							-TimeoutMs (200 + (($snapAttempt - 1) * 150))
						$snapVerified = $snapWait.Verified

						if ($snapVerified) {
							if (Test-LogVerbose) {
								$retryLabel = if ($snapAttempt -gt 1) { " (attempt $snapAttempt)" } else { "" }
								Write-LogDebug "     ✓ Snapped [$title] → Win+$direction (verified at zone position)$retryLabel" -Style Success
							}
							break
						}

						# If keyboard snap failed, try shift-drag snapping as fallback
						Write-LogDebug "     ⚠ Keyboard snap unverified for [$title], attempting shift-drag snap..." -Style Warning

						# First reposition the window to the inset position for shift-drag
						try {
							$null = Resize-Windows `
								-WindowHandle $handle `
								-TargetX $expectedX `
								-TargetY $expectedY `
								-TargetWidth $expectedWidth `
								-TargetHeight $expectedHeight `
								-InsetPercent $insetPercent
							Start-Sleep -Milliseconds 10
						}
						catch {
							# Continue anyway
						}

						# Perform shift-drag snap using the native consolidated method.
						# Browser tabs should always drag from the left inset to avoid tab detachment.
						# Other apps keep the rotating start-point behavior across retries.
						$isBrowserWindow = [WindowModule.Native]::IsBrowserWindow($handle)
						$dragStartMode = if ($isBrowserWindow) {
							0
						}
						else {
							switch ($snapAttempt) {
								1 { 0 }
								2 { 1 }
								default { 2 }
							}
						}
						$dragStartLabel = switch ($dragStartMode) {
							0 { 'left-inset' }
							1 { 'top-center' }
							default { 'top-right-third-center' }
						}

						if (Test-LogVerbose) {
							$windowTypeLabel = if ($isBrowserWindow) { 'browser' } else { 'non-browser' }
							Write-LogDebug "     ↳ Shift-drag start point: $dragStartLabel [$windowTypeLabel]"
						}

						$shiftDragResult = [WindowModule.Native]::ShiftDragSnap($handle, $expectedX, $expectedY, $expectedWidth, $expectedHeight, $dragStartMode)

						if ($shiftDragResult) {
							# Same poll-until-verified pattern as the keyboard snap above.
							$dragWait = Wait-WindowRect -WindowHandle $handle `
								-ExpectedX $expectedX -ExpectedY $expectedY `
								-ExpectedWidth $expectedWidth -ExpectedHeight $expectedHeight `
								-TimeoutMs (250 + (($snapAttempt - 1) * 150))
							$snapVerified = $dragWait.Verified
						}

						if ($snapVerified) {
							if (Test-LogVerbose) {
								$retryLabel = if ($snapAttempt -gt 1) { " (attempt $snapAttempt)" } else { "" }
								Write-LogDebug "     ✓ Snapped [$title] → Shift+Drag (verified at zone position)$retryLabel" -Style Success
							}
							break
						}

						# Not verified on this attempt
						if ($snapAttempt -eq $maxSnapRetries) {
							# Final attempt exhausted - record the failure and CONTINUE with the
							# remaining windows and desktops, so one stubborn window no longer
							# strands everything after it at its inset size. The outer retry in
							# Set-WorkspaceWindowLayout re-runs the full layout for the recorded
							# failures; only the circuit breaker below aborts the pass early.
							$errorDetails = "Snap FAILED for [$title] after $maxSnapRetries attempts (unverified position)"
							$expectedBounds = "($expectedX, $expectedY) ${expectedWidth}x${expectedHeight}"
							$actualBounds = $null
							$postFinalRect = New-Object WindowModule.RECT
							if ([WindowModule.Native]::GetWindowRect($handle, [ref]$postFinalRect)) {
								$finalX = $postFinalRect.Left; $finalY = $postFinalRect.Top
								$finalW = $postFinalRect.Right - $postFinalRect.Left; $finalH = $postFinalRect.Bottom - $postFinalRect.Top
								$errorDetails += "`n  Expected => ($expectedX, $expectedY) ${expectedWidth}x${expectedHeight}"
								$errorDetails += "`n  Actual   => ($finalX, $finalY) ${finalW}x${finalH}"
								$actualBounds = "($finalX, $finalY) ${finalW}x${finalH}"
							}
							$failedSnaps.Add([PSCustomObject]@{
									Handle      = $handle
									WindowTitle = $title
									ProcessName = $windowState.ProcessName
									Expected    = $expectedBounds
									Actual      = $actualBounds
									Error       = $errorDetails
								})
							Write-LogDebug "     ✗ $errorDetails" -Style Error
							if ($failedSnaps.Count -ge $maxFailedWindows) {
								Write-LogDebug "     ✗ [$($failedSnaps.Count)] window(s) failed this pass - aborting (systemic failure, caller resets and retries)" -Style Error
								$snapAborted = $true
							}
							break
						}
					}
					catch {
						if ($snapAttempt -eq $maxSnapRetries) {
							# All retries exhausted - record and move on (see the unverified
							# branch above for why the pass continues).
							$failedSnaps.Add([PSCustomObject]@{
									Handle      = $handle
									WindowTitle = $title
									ProcessName = $windowState.ProcessName
									Expected    = "($expectedX, $expectedY) ${expectedWidth}x${expectedHeight}"
									Actual      = $null
									Error       = "Snap FAILED for [$title] after $maxSnapRetries attempts => $_"
								})
							Write-LogDebug "     ✗ Snap FAILED for [$title] after $maxSnapRetries attempts => $_" -Style Error
							if ($failedSnaps.Count -ge $maxFailedWindows) {
								Write-LogDebug "     ✗ [$($failedSnaps.Count)] window(s) failed this pass - aborting (systemic failure, caller resets and retries)" -Style Error
								$snapAborted = $true
							}
							break
						}
						elseif (Test-LogVerbose) {
							Write-Warning "`n  ✗ Failed to snap [$title] (attempt $snapAttempt) => $_"
						}
					}
				}

				if ($snapAborted) { break }

				if ($snapVerified) {
					$snappedCount++
				}
			}

			if ($snapAborted) { break }
		}

		# Post-pass desktop verification sweep. The per-window alignment check above answers
		# "was this window on its desktop right before ITS turn", not "is every window still
		# there after the whole pass": the upstream Move-Window falls back to moving a
		# process's MAIN window when the requested view cannot be moved, so positioning a
		# later sibling of a multi-window process (Firefox, Windows Terminal, VS Code) can
		# silently displace an already-placed window. Same pattern as the Move-Windows sweep:
		# one cheap desktop read per tracked window, one recovery attempt, unrecoverable =>
		# failure. Cross-desktop moves do not need the target desktop visible, so no desktop
		# switching happens here - and the sweep runs even after an abort, because bringing a
		# displaced window home needs neither FancyZones nor further snapping.
		$failedSweepHandles = [System.Collections.Generic.HashSet[IntPtr]]::new()
		foreach ($failure in $failedSnaps) {
			if ($failure.Handle -and $failure.Handle -ne [IntPtr]::Zero) {
				[void]$failedSweepHandles.Add($failure.Handle)
			}
		}

		foreach ($windowState in $script:PositionedWindowHandles) {
			$sweepHandle = $windowState.Handle
			if (-not $sweepHandle -or $sweepHandle -eq [IntPtr]::Zero) { continue }
			# Already reported as failed - the workspace retry re-places it anyway.
			if ($failedSweepHandles.Contains($sweepHandle)) { continue }

			$sweepDesktopNum = if ($null -ne $windowState.DesktopNumber) { $windowState.DesktopNumber } else { 1 }
			$expectedDesktopIndex = ConvertTo-InternalDesktopIndex -DesktopNumber $sweepDesktopNum -DesktopOffset $DesktopOffset

			$sweepIndex = Get-WindowDesktopIndex -WindowHandle $sweepHandle
			# -1 means "cannot tell" (window closed mid-pass, pinned) - leave it be.
			if ($sweepIndex -lt 0 -or $sweepIndex -eq $expectedDesktopIndex) { continue }

			Write-LogDebug "  ! [$($windowState.WindowTitle)] is on desktop $($sweepIndex + 1) after the pass (expected $($expectedDesktopIndex + 1)) - retrying" -Style Warning

			$recovered = $false
			try {
				$recovered = [bool](Move-WindowToVirtualDesktop -WindowHandle $sweepHandle -DesktopNumber $expectedDesktopIndex)
			}
			catch {
				$recovered = $false
			}

			if ($recovered) {
				# A desktop move does not change the window rect, so the placement this pass
				# verified still stands - only the desktop assignment needed repair.
				Write-LogDebug "  ✓ Recovered [$($windowState.WindowTitle)] => desktop $($expectedDesktopIndex + 1)" -Style Success
			}
			else {
				$failedSnaps.Add([PSCustomObject]@{
						Handle      = $sweepHandle
						WindowTitle = $windowState.WindowTitle
						ProcessName = $windowState.ProcessName
						Expected    = "desktop $($expectedDesktopIndex + 1)"
						Actual      = "desktop $($sweepIndex + 1)"
						Error       = "Window [$($windowState.WindowTitle)] left desktop $($expectedDesktopIndex + 1) during the pass and could not be brought back"
					})
			}
		}

		if ($failedSnaps.Count -gt 0) {
			# A failed/aborted pass is exactly when an interrupted sequence may have
			# stranded a modifier or the shift-drag's mouse button. Leave the session
			# clean before the caller's rerun path respawns the shell.
			$null = Reset-KeyboardModifiers -IncludeMouseButton

			Write-LogWarning "Snapped [$snappedCount] window(s), but [$($failedSnaps.Count)] failed:"
			foreach ($failure in $failedSnaps) {
				Write-LogError "   $($failure.Error)" -NoLeadingNewline
			}
		}
		elseif (Test-LogVerbose) {
			Write-LogDebug "Successfully snapped [$snappedCount] window(s) to FancyZones!" -Style Success
		}

		$script:LastSnapAllWindowsResult = [PSCustomObject]@{
			SnappedCount  = $snappedCount
			FailedWindows = @($failedSnaps)
		}
	}
}
