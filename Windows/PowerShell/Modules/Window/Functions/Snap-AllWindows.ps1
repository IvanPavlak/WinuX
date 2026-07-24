function Snap-AllWindows {
	<#
	.SYNOPSIS
		Snaps all windows to FancyZones by sending Win+Up or Win+Down based on window position.
	.DESCRIPTION
		Intelligently snaps windows to FancyZones by:
		- Grouping windows by virtual desktop and switching desktops as needed
		- Sending Win+Up for most windows (default)
		- Detecting windows in the top position that are vertically split (roughly 40-60% height)
		- Sending Win+Down for those top-split windows
		- Using reliable focus acquisition with thread attachment

		A window is considered "top and vertically split" if:
		- It's in the top half of the monitor
		- Its height is approximately 40-60% of the monitor height (vertically split)

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
		Delay in milliseconds between each window snap operation. Default is 25ms.
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

		$fancyZonesReady = Start-FancyZones
		if (-not $fancyZonesReady) {
			$fancyZonesReady = Start-FancyZones -ForceRestart -MaxWaitSeconds 20
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

		# Calculate inset values with the same helper used by Set-WindowLayouts
		$insetPercent = 0.05

		# Re-check FancyZones liveness during long-running multi-desktop loops.
		$ensureFancyZonesRunning = {
			$runningFancyZones = Get-Process -Name "PowerToys.FancyZones" -ErrorAction SilentlyContinue
			if ($runningFancyZones) {
				return $true
			}

			Write-LogDebug "  ⚠ FancyZones process is not running, attempting restart..." -Style Warning

			$restartReady = Start-FancyZones -ForceRestart -MaxWaitSeconds 20
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

			if ($snapAborted) { break }

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
				$windowTop = $rect.Top
				$windowBottom = $rect.Bottom
				$windowHeight = $windowBottom - $windowTop
				$windowCenterX = ($rect.Left + $rect.Right) / 2
				$windowCenterY = ($windowTop + $windowBottom) / 2

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

				# Default direction is UP (true = up, false = down for SendSnapKey)
				$direction = "Up"
				$snapUp = $true

				# Check if window is in top position and vertically split
				$monitorBounds = $windowMonitor.Bounds
				$monitorTop = $monitorBounds.Top
				$monitorHeight = $monitorBounds.Height
				$monitorMiddleY = $monitorTop + ($monitorHeight / 2)

				# Calculate height ratio relative to monitor
				$heightRatio = $windowHeight / $monitorHeight

				# Window is considered "top and vertically split" if:
				# 1. Window top is at or near the monitor top (within 100px tolerance)
				# 2. Window height is roughly 40-60% of monitor height (vertically split)
				# 3. Window center is in the top half of the monitor
				$isAtTop = ($windowTop -le ($monitorTop + 100))
				$isVerticallySplit = ($heightRatio -ge 0.35 -and $heightRatio -le 0.65)
				$isInTopHalf = ($windowCenterY -lt $monitorMiddleY)

				if ($isAtTop -and $isVerticallySplit -and $isInTopHalf) {
					$direction = "Down"
					$snapUp = $false
				}

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
							# Final attempt exhausted - abort immediately so the outer retry logic
							# in Set-WorkspaceWindowLayout can rerun the workspace command.
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
							$snapAborted = $true
							break
						}
					}
					catch {
						if ($snapAttempt -eq $maxSnapRetries) {
							# All retries exhausted - abort immediately
							$failedSnaps.Add([PSCustomObject]@{
									Handle      = $handle
									WindowTitle = $title
									ProcessName = $windowState.ProcessName
									Expected    = "($expectedX, $expectedY) ${expectedWidth}x${expectedHeight}"
									Actual      = $null
									Error       = "Snap FAILED for [$title] after $maxSnapRetries attempts => $_"
								})
							Write-LogDebug "     ✗ Snap FAILED for [$title] after $maxSnapRetries attempts => $_" -Style Error
							$snapAborted = $true
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
