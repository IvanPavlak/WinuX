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

		A window that exhausts its attempts (keyboard snap and shift-drag, three times) is
		not treated as a stubborn window but as the signal that the zone grid it was snapped
		against is wrong: the pass resets FancyZones ONCE for it (-ZoneReset, or a plain
		FancyZones restart when the caller supplied none), re-confirms the window's desktop,
		re-insets the window and runs the whole attempt budget a second time for the SAME
		window before touching the next one. Only a window that fails that second round is
		recorded as failed, and the pass then continues with the remaining windows. Two resets
		per pass at most - two resets that did not help are systemic, and the third exhausted
		window records without one - and a circuit breaker still aborts the pass once several
		windows have failed, handing it back to the caller's retry. After the
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
	.PARAMETER DesktopNumbers
		Restricts the positioned-windows pass to the tracked windows on these desktops (the
		1-based numbers Add-PositionedWindow recorded, offset already folded in). Used by
		Set-WorkspaceWindowLayout to snap one desktop as soon as its windows are stable while
		the rest are still loading. Default (empty) processes every tracked window.
	.PARAMETER ZoneReset
		Scriptblock run when a window exhausts its snap attempts, before the second round for
		that window; receives one string argument, the reason. Set-WorkspaceWindowLayout passes
		its FancyZones reset (force-restart plus Apply-FancyZones -Force). When omitted the
		recovery is a FancyZones force-restart alone - a standalone call has no monitor
		configuration to re-apply the zone layouts with.
	.EXAMPLE
		Snap-AllWindows
		# Snaps positioned windows to FancyZones (workspace flow)
	.EXAMPLE
		Snap-AllWindows -DesktopNumbers 2 -ZoneReset { param($Reason) Start-FancyZones -ForceRestart; Apply-FancyZones -MonitorConfig $config.Monitors -Force }
		# Snaps only the tracked windows on desktop 2, resetting the zone grid through the caller's scriptblock when one exhausts its attempts
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
		[int]$DesktopCount = 0,

		# Restrict the positioned-windows pass to these tracked desktop numbers (1-based, offset
		# folded in). Empty processes every tracked window.
		[Parameter()]
		[int[]]$DesktopNumbers,

		# Zone-grid reset run once for a window that exhausted its attempts, before its second
		# round. Restart-only when omitted.
		[Parameter()]
		[scriptblock]$ZoneReset
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

		# A window that exhausted keyboard AND shift-drag is not a window problem - it is the same
		# wedged-FancyZones signal the circuit breaker above waits three windows for, and carrying
		# on snaps the rest of the pass against a grid that may be wrong, only for the caller's
		# retry to pay a full position-snap-verify cycle afterwards. So the grid is reset right
		# there, ONCE per window, and the same window gets its whole attempt budget again before
		# anything is recorded. Two resets per pass at most: two resets that did not help ARE the
		# systemic signal, and the third exhausted window records without one so the caller's
		# retry and the rerun escalation take over as before.
		$maxZoneResetsPerPass = 2
		$zoneResetsThisPass = 0

		$recoverZoneGrid = {
			param([string]$Reason, [int]$InternalDesktopIndex, [int]$DisplayDesktopNumber)

			Write-LogWarning "   Snap exhausted for $Reason - resetting FancyZones and retrying the same window..." -NoLeadingNewline

			# Synthesized input from the failed attempts may have stranded a modifier or the
			# shift-drag's mouse button.
			$null = Reset-KeyboardModifiers -IncludeMouseButton

			if ($ZoneReset) {
				try {
					$null = & $ZoneReset "snap exhausted for $Reason"
				}
				catch {
					Write-LogWarning "   Zone reset failed: $($_.Exception.Message)" -NoLeadingNewline
				}
			}
			else {
				# No caller-supplied reset (standalone call): restart FancyZones. There is no
				# monitor configuration here to re-apply the zone layouts with.
				try {
					$null = Start-FancyZones -ForceRestart -MaxWaitSeconds 20 -PassThru
				}
				catch {
					Write-LogWarning "   FancyZones restart failed: $($_.Exception.Message)" -NoLeadingNewline
				}
			}

			# The reset may have moved the active desktop (the shortcut fallback of the zone
			# re-apply ends elsewhere), and the snap needs the window's desktop visible.
			$backOnDesktop = $false
			try {
				$null = Switch-Desktop -Desktop $InternalDesktopIndex -ErrorAction Stop
				$backOnDesktop = [bool](Wait-DesktopSwitch -TargetDesktopIndex $InternalDesktopIndex)
			}
			catch {
				$backOnDesktop = $false
			}
			if (-not $backOnDesktop) {
				Write-LogDebug "  ⚠ Could not return to desktop [$DisplayDesktopNumber] after the zone reset - recording the failure" -Style Warning
				return $false
			}

			# Windows and monitors may have moved during the restart - never snap against a stale
			# enumeration.
			Clear-WindowCache
			Clear-MonitorCache
			return $true
		}

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
			# A per-desktop call (Set-WorkspaceWindowLayout snapping one desktop while the others
			# are still loading) leaves every other tracked window alone.
			if ($DesktopNumbers -and $DesktopNumbers.Count -gt 0 -and $DesktopNumbers -notcontains [int]$desktopNum) { continue }
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
					$snap = $null
					$singleZoneAttempts = 0
					$singleZoneReset = $false
					for ($snapRound = 1; $snapRound -le 2; $snapRound++) {
						$snap = Invoke-SingleZoneWindowSnap -WindowHandle $handle `
							-TargetX $expectedX -TargetY $expectedY `
							-TargetWidth $expectedWidth -TargetHeight $expectedHeight `
							-WindowTitle $expectedTitle -InsetPercent $insetPercent
						$singleZoneAttempts += [int]$snap.Attempts
						if ($snap.Verified) { break }

						# Exhausted: reset the zone grid once and run the budget again for THIS window.
						if ($snapRound -eq 1 -and $zoneResetsThisPass -lt $maxZoneResetsPerPass) {
							$zoneResetsThisPass++
							$singleZoneReset = $true
							if (& $recoverZoneGrid "[$expectedTitle]" $internalDesktopIndex $desktopNum) { continue }
						}
						break
					}

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
						$resetNote = if ($singleZoneReset) { ", zone grid reset once" } else { "" }
						$errorDetails = "Single-zone snap FAILED for [$expectedTitle] after $singleZoneAttempts attempts (unverified position$resetNote)"
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

				# Snap through the attempt budget (Win+Up, shift-drag fallback, three attempts -
				# Invoke-MultiZoneWindowSnap), and when it is exhausted reset the zone grid ONCE and
				# run the budget again for THIS window before anything is recorded.
				$snapVerified = $false
				$snap = $null
				$multiZoneAttempts = 0
				$multiZoneReset = $false
				for ($snapRound = 1; $snapRound -le 2; $snapRound++) {
					$snap = Invoke-MultiZoneWindowSnap -WindowHandle $handle `
						-ExpectedX $expectedX -ExpectedY $expectedY `
						-ExpectedWidth $expectedWidth -ExpectedHeight $expectedHeight `
						-WindowTitle $title -InsetPercent $insetPercent
					$multiZoneAttempts += [int]$snap.Attempts
					if ($snap.Verified) {
						$snapVerified = $true
						break
					}

					if ($snapRound -eq 1 -and $zoneResetsThisPass -lt $maxZoneResetsPerPass) {
						$zoneResetsThisPass++
						$multiZoneReset = $true
						if (& $recoverZoneGrid "[$title]" $internalDesktopIndex $desktopNum) {
							# Round two starts from the inset, exactly like the first attempt did.
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
								# Continue anyway - the snap verifies.
							}
							continue
						}
					}
					break
				}

				if (-not $snapVerified) {
					# Recorded, and the pass CONTINUES with the remaining windows and desktops so
					# one window cannot strand everything after it at its inset size. The caller's
					# retry re-runs the full layout for the recorded failures; only the circuit
					# breaker below aborts the pass early.
					$resetNote = if ($multiZoneReset) { ", zone grid reset once" } else { "" }
					$errorDetails = if ($snap.Error) {
						"Snap FAILED for [$title] after $multiZoneAttempts attempts$resetNote => $($snap.Error)"
					}
					else {
						"Snap FAILED for [$title] after $multiZoneAttempts attempts (unverified position$resetNote)"
					}
					$expectedBounds = "($expectedX, $expectedY) ${expectedWidth}x${expectedHeight}"
					$actualBounds = $null
					if ($null -ne $snap.X) {
						$actualBounds = "($($snap.X), $($snap.Y)) $($snap.Width)x$($snap.Height)"
						$errorDetails += "`n  Expected => $expectedBounds"
						$errorDetails += "`n  Actual   => $actualBounds"
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
			$sweepDesktopFilterNum = if ($null -ne $windowState.DesktopNumber) { $windowState.DesktopNumber } else { 1 }
			if ($DesktopNumbers -and $DesktopNumbers.Count -gt 0 -and $DesktopNumbers -notcontains [int]$sweepDesktopFilterNum) { continue }
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
