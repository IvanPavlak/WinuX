function Center-Windows {
	<#
	.SYNOPSIS
		Centers all open windows on their respective monitors.

	.DESCRIPTION
		Enumerates all visible application windows, determines which monitor each
		window is currently on (based on its center point), then moves and resizes
		every window to a centered position within that monitor's work area.

		Pass -Monitor to center every matched window on ONE explicit monitor instead
		of deriving a monitor per window. This matters when centering follows a
		monitor consolidation pass (Reset-Windows): deriving the monitor from each
		window's current rectangle re-homes any window that something else moved in
		the meantime, cementing the stray placement, whereas an explicit target
		re-asserts the intended monitor and makes the pass self-correcting.

		By default, windows are resized to 40% of the monitor work area width and
		50% of the height. Use -WidthPercent and -HeightPercent to customize.

		Filtering mirrors Move-Windows: pass -ProcessName and/or -WindowTitle to
		center only matching windows (exact, wildcard, and regex, with OR logic when
		both are provided), delegated to Get-WindowHandle. When neither is supplied,
		all visible application windows are centered.

		The actual move/resize is delegated to Resize-Windows in target-bounds mode
		(with -InsetPercent 0 for exact placement), so window placement flows through
		a single source of truth (DRY) shared with the layout/snap pipeline. Each
		placement is then verified with Wait-WindowRect and re-applied once when the
		window did not land on the centered bounds - SetWindowPos reports success for
		the call even when an external window manager (FancyZones restoring a
		remembered zone) moves the window straight back.

		That check passes on its first read, so it cannot see a window that is moved
		again a few hundred milliseconds later (FancyZones restoring a remembered
		zone after a desktop collapse, an Electron app such as Obsidian or VS Code
		re-applying its own saved bounds). After the pass, up to three convergence
		rounds therefore wait 250 ms, re-enumerate the windows fresh, and compare
		each one with the bounds it was centered on: a window that moved is
		re-centered, a window that was not in the first enumeration is centered, and
		the final round only checks, recording any window still off its bounds as
		failed. Each window is re-centered at most twice, and the loop stops at the
		first round that finds nothing to do. Windows that would not hold the
		centered bounds are reported in normal mode as well as under verbose logging,
		so a partial pass never looks like a complete one.

		Uses existing module functions:
		- Get-WindowHandle for pattern-based window filtering (wildcard, regex, exact)
		- Get-CachedWindows for fast window enumeration (when no filters)
		- Get-MonitorInfo for monitor bounds and work areas
		- Resolve-TargetMonitor for -Monitor resolution (index, label, device name)
		- Resize-Windows for reliable, centralized window placement
		- Wait-WindowRect for post-placement verification
		- Ensure-WindowsFormsLoaded for System.Windows.Forms dependency

	.PARAMETER WidthPercent
		The percentage of the monitor work area width to use for each window.
		Default is 40. Range: 10-100.

	.PARAMETER HeightPercent
		The percentage of the monitor work area height to use for each window.
		Default is 50. Range: 10-100.

	.PARAMETER ProcessName
		Optional. Only center windows belonging to processes matching this pattern (without .exe).
		Supports exact names, wildcard patterns (*, ?), and regex.
		Can be used alone or combined with WindowTitle (OR logic).
		When omitted (and no WindowTitle), all visible application windows are centered.

	.PARAMETER WindowTitle
		Optional. Only center windows whose title matches this pattern.
		Supports wildcard patterns (*, ?) and regex.
		Can be used alone or combined with ProcessName (OR logic).
		When omitted (and no ProcessName), all visible application windows are centered.

	.PARAMETER OnPrimary
		If specified, every matched window is centered on the primary monitor
		(whichever monitor is currently primary), regardless of which monitor it
		is currently on. Without this switch, each window is centered on the
		monitor it already lives on. Cannot be combined with -Monitor.

	.PARAMETER Monitor
		Centers every matched window on this monitor, regardless of which monitor
		it is currently on. Accepts a 1-based index ("2"), a label ("Primary",
		"Secondary", "Monitor3"), or a device name ("\\.\DISPLAY1") - resolved by
		Resolve-TargetMonitor, the same path Move-Windows uses. Cannot be combined
		with -OnPrimary.

	.EXAMPLE
		Center-Windows
		Centers all windows at 40% width and 50% height on their current monitors.

	.EXAMPLE
		Center-Windows -WidthPercent 60 -HeightPercent 70
		Centers all windows at 60% width and 70% height.

	.EXAMPLE
		Center-Windows -ProcessName "chrome"
		Centers only Chrome windows (exact match).

	.EXAMPLE
		Center-Windows -ProcessName "*chrome*"
		Centers windows whose process name contains "chrome" (wildcard match).

	.EXAMPLE
		Center-Windows -ProcessName "(chrome|firefox|msedge)"
		Centers windows belonging to any of the listed browser processes (regex match).

	.EXAMPLE
		Center-Windows -WindowTitle "*YouTube*"
		Centers windows with "YouTube" in the title.

	.EXAMPLE
		Center-Windows -WidthPercent 50 -HeightPercent 50
		Centers all windows at half the monitor size.

	.EXAMPLE
		Center-Windows -ProcessName "WindowsTerminal" -OnPrimary
		Centers Windows Terminal on the primary monitor, pulling it back from a
		secondary monitor if it currently lives there.

	.EXAMPLE
		Center-Windows -Monitor 2
		Centers every window on monitor 2, pulling back any window that currently
		sits on another monitor.
	#>
	[CmdletBinding(DefaultParameterSetName = 'CurrentMonitor')]
	param (
		[Parameter()]
		[ValidateRange(10, 100)]
		[int]$WidthPercent = 40,

		[Parameter()]
		[ValidateRange(10, 100)]
		[int]$HeightPercent = 50,

		[Parameter()]
		[string]$ProcessName,

		[Parameter()]
		[string]$WindowTitle,

		[Parameter(ParameterSetName = 'OnPrimary')]
		[switch]$OnPrimary,

		[Parameter(ParameterSetName = 'TargetMonitor')]
		[AllowEmptyString()]
		[string]$Monitor
	)

	begin {
		# Ensure Windows Forms is loaded for monitor detection
		Ensure-WindowsFormsLoaded
	}

	process {
		# Only call it "All Windows" when no filter narrows the set; otherwise just "Windows".
		$scopeText = if ($ProcessName -or $WindowTitle) { "Windows" } else { "All Windows" }
		Write-LogTitle "Centering $scopeText"

		# Get monitor information using existing cached function
		$monitors = Get-MonitorInfo -Quiet

		if (-not $monitors -or $monitors.Count -eq 0) {
			Write-Warning "`n No monitors detected. Cannot center windows!"
			return
		}

		# Resolve the forced target monitor once, if any: -OnPrimary is the shorthand for
		# "whichever monitor is currently primary", -Monitor takes an index, label, or device
		# name. With neither, each window is centered on the monitor it currently occupies.
		$forcedMonitor = $null
		$forcedMonitorLabel = $null
		if ($OnPrimary) {
			$forcedMonitor = $monitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
			if (-not $forcedMonitor) {
				$forcedMonitor = $monitors[0]
			}
			$forcedMonitorLabel = 'Primary'
		}
		elseif (-not [string]::IsNullOrWhiteSpace($Monitor)) {
			$resolvedMonitor = Resolve-TargetMonitor -Monitor $Monitor -MonitorInfo $monitors
			if (-not $resolvedMonitor.Monitor) {
				Write-LogError $resolvedMonitor.ErrorMessage
				return
			}
			$forcedMonitor = $resolvedMonitor.Monitor
			$forcedMonitorLabel = $resolvedMonitor.Label
		}

		if ($forcedMonitorLabel) {
			Write-LogDebug "Centering on monitor $forcedMonitorLabel ($($forcedMonitor.DeviceName))"
		}

		if (Test-LogVerbose) {
			Write-LogDebug "Detected $($monitors.Count) monitor(s)!" -Style Step
			foreach ($mon in $monitors) {
				$label = if ($mon.IsPrimary) { "Primary" } else { $mon.DeviceName }
				Write-LogDebug "$label => Work Area ($($mon.WorkAreaLeft), $($mon.WorkAreaTop)) [$($mon.WorkAreaWidth)x$($mon.WorkAreaHeight)]" -Style Step
			}
		}

		# Resolve the target window set.
		# Clear cache first to read fresh positions for monitor detection.
		# - ProcessName/WindowTitle: delegate filtering to Get-WindowHandle (exact, wildcard,
		#   regex, OR logic) - the same matching path used by Move-Windows.
		# - Neither: all visible windows.
		Clear-WindowCache

		$hasFilter = $ProcessName -or $WindowTitle
		if ($hasFilter) {
			$filterParams = @{}
			if ($ProcessName) { $filterParams.ProcessName = $ProcessName }
			if ($WindowTitle) { $filterParams.WindowTitle = $WindowTitle }
			$allWindows = Get-WindowHandle @filterParams
		}
		else {
			$allWindows = Get-CachedWindows
		}

		# System windows to skip
		$skipTitles = @(
			'Program Manager',
			'Windows Input Experience',
			'TextInputHost',
			'Search',
			'Start',
			'Action center',
			'Microsoft Text Input Application',
			'Windows Shell Experience Host',
			'NVIDIA GeForce Overlay',
			'Setup',
			''
		)

		# Two placement attempts with a short verification budget per window keeps the worst
		# case bounded for a full-desktop pass (same budget as the Move-Windows monitor leg).
		$placementAttempts = 2
		$placementVerifyTimeoutMs = 150
		$excludedTitleCount = 0
		$excludedInvalidSizeCount = 0
		$totalEnumeratedWindows = @($allWindows).Count
		$totalEligibleWindows = 0

		# One record per eligible window, keyed by handle: the centered bounds it was given
		# (Target) and whether it holds them ('Centered') or not ('Failed'). The convergence
		# rounds below re-check every window against its RECORDED bounds and overwrite the
		# category as they learn more, and the summary is derived from this map at the end - the
		# same shape as the Move-Windows outcome records. $outcomeOrder keeps first-seen order
		# for the printed lists.
		$outcomes = @{}
		$outcomeOrder = [System.Collections.Generic.List[string]]::new()
		$recordOutcome = {
			param($Handle, $Category, $Label, $Target)
			$key = [string]$Handle
			if (-not $outcomes.ContainsKey($key)) { $outcomeOrder.Add($key) }
			$outcomes[$key] = @{ Category = $Category; Label = $Label; Target = $Target }
		}

		# The centered bounds for a window. With -OnPrimary or -Monitor every window is forced
		# onto the resolved monitor; otherwise the monitor under the window's center point is
		# used, falling back to the primary monitor for a window that sits off-screen.
		$resolveTarget = {
			param($Window)

			if ($forcedMonitor) {
				$targetMonitor = $forcedMonitor
			}
			else {
				$windowCenterX = $Window.Left + [math]::Floor($Window.Width / 2)
				$windowCenterY = $Window.Top + [math]::Floor($Window.Height / 2)

				$targetMonitor = $null
				foreach ($mon in $monitors) {
					if ($windowCenterX -ge $mon.Left -and $windowCenterX -lt $mon.Right -and
						$windowCenterY -ge $mon.Top -and $windowCenterY -lt $mon.Bottom) {
						$targetMonitor = $mon
						break
					}
				}

				if (-not $targetMonitor) {
					$targetMonitor = $monitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
					if (-not $targetMonitor) {
						$targetMonitor = $monitors[0]
					}

					Write-LogDebug "  [$($Window.Title)] is off-screen, moving to primary monitor!" -Style Warning
				}
			}

			$targetWidth = [math]::Floor($targetMonitor.WorkAreaWidth * $WidthPercent / 100)
			$targetHeight = [math]::Floor($targetMonitor.WorkAreaHeight * $HeightPercent / 100)
			return @{
				X      = $targetMonitor.WorkAreaLeft + [math]::Floor(($targetMonitor.WorkAreaWidth - $targetWidth) / 2)
				Y      = $targetMonitor.WorkAreaTop + [math]::Floor(($targetMonitor.WorkAreaHeight - $targetHeight) / 2)
				Width  = $targetWidth
				Height = $targetHeight
			}
		}

		# Place one window on its centered bounds and verify it.
		#
		# The move/resize is delegated to Resize-Windows in target-bounds mode. InsetPercent 0
		# places the window at the exact centered bounds (no FancyZones inset), keeping all
		# placement on the shared Resize-Windows path (DRY). Bound explicitly, so it deliberately
		# overrides the configurable Get-WindowInsetPercent default rather than tracking it -
		# centering is exact placement, never an inset pre-snap position.
		#
		# The placement is then VERIFIED and re-applied once, the same way Move-Windows treats its
		# monitor placement: SetWindowPos reports success for the call, not for where the window
		# ends up. This check only proves the window got there; whether it STAYS there is what the
		# convergence rounds below establish.
		$placeWindow = {
			param($Handle, $Title, $ProcName, $Target)

			$lastObserved = $null
			for ($attempt = 1; $attempt -le $placementAttempts; $attempt++) {
				$null = Resize-Windows -WindowHandle $Handle -TargetX $Target.X -TargetY $Target.Y -TargetWidth $Target.Width -TargetHeight $Target.Height -InsetPercent 0
				$resizeResult = $script:LastResizeWindowsResult

				if (-not ($resizeResult -and $resizeResult.ResizedCount -gt 0)) {
					continue
				}

				$placementCheck = Wait-WindowRect -WindowHandle $Handle `
					-ExpectedX $Target.X -ExpectedY $Target.Y `
					-ExpectedWidth $Target.Width -ExpectedHeight $Target.Height `
					-TimeoutMs $placementVerifyTimeoutMs

				if ($placementCheck.Verified) {
					return @{ Placed = $true; Observed = $placementCheck }
				}

				$lastObserved = $placementCheck
				Write-LogDebug "     ! [$Title] ($ProcName) did not hold the centered bounds on attempt $attempt (observed $($placementCheck.X), $($placementCheck.Y))" -Style Warning
			}

			return @{ Placed = $false; Observed = $lastObserved }
		}

		foreach ($window in $allWindows) {
			$handle = $window.Handle
			$title = $window.Title
			$procName = $window.ProcessName

			# Skip system/shell windows
			if ($title -in $skipTitles) {
				$excludedTitleCount++
				continue
			}

			# Skip windows with no meaningful size (hidden or not real)
			if ($window.Width -le 0 -or $window.Height -le 0) {
				$excludedInvalidSizeCount++
				continue
			}

			$totalEligibleWindows++

			$target = & $resolveTarget $window
			$placement = & $placeWindow $handle $title $procName $target
			$label = Get-WindowDisplayName -ProcessName $procName -Title $title

			if ($placement.Placed) {
				& $recordOutcome $handle 'Centered' $label $target
				Write-LogDebug "     ✓ Centered [$title] ($procName) => ($($target.X), $($target.Y)) [$($target.Width)x$($target.Height)]" -Style Success
			}
			else {
				& $recordOutcome $handle 'Failed' $label $target
				$observedText = if ($placement.Observed) { " (last observed $($placement.Observed.X), $($placement.Observed.Y))" } else { '' }
				Write-LogDebug "     ✗ Failed to center [$title] ($procName)$observedText" -Style Warning
			}
		}

		# Convergence rounds: the pass ends only once every window is SEEN holding its centered
		# bounds after a settle delay. The per-window check above passes on its first read,
		# because SetWindowPos on another process's window returns only after that window has
		# handled the move - so a window that is moved again a few hundred milliseconds later
		# was counted as centered and never looked at again. Two things do exactly that during a
		# reset: FancyZones restoring a remembered zone for a window that just arrived on the
		# collapsed desktop, and Electron apps (Obsidian, VS Code) re-applying their own saved
		# bounds after being restored and resized.
		#
		# Each round waits $roundSettleMs (longer than the per-window verify budget the drift
		# escaped), re-enumerates the windows FRESH and compares each one with the bounds it was
		# RECORDED with, not with bounds re-derived from where it is now - a window dragged onto
		# another monitor must come back to where it was centered. A window off its bounds is
		# re-placed; a window that was not in the first enumeration (no title yet while it
		# loaded) is centered now. The final round only checks: a window still off its bounds
		# there is recorded as failed, so every window is re-placed at most
		# ($convergenceRounds - 1) times and the summary never trusts a re-placement nobody
		# looked at afterwards. The loop ends early on the first round that finds nothing to do.
		$convergenceRounds = 3
		$roundSettleMs = 250
		$tolerancePx = $script:WindowModuleTolerances.PositionVerificationPx

		for ($round = 1; $round -le $convergenceRounds; $round++) {
			$isFinalRound = ($round -eq $convergenceRounds)

			Start-Sleep -Milliseconds $roundSettleMs
			Clear-WindowCache
			$roundWindows = if ($hasFilter) { Get-WindowHandle @filterParams } else { Get-CachedWindows }

			$stragglers = @()
			foreach ($window in @($roundWindows)) {
				if ($window.Title -in $skipTitles) { continue }
				if ($window.Width -le 0 -or $window.Height -le 0) { continue }

				$key = [string]$window.Handle
				if (-not $outcomes.ContainsKey($key)) {
					$stragglers += @{ Window = $window; Target = (& $resolveTarget $window); IsNew = $true }
					continue
				}

				$record = $outcomes[$key]
				$target = $record.Target
				$holds = ([Math]::Abs($window.Left - $target.X) -le $tolerancePx) -and
					([Math]::Abs($window.Top - $target.Y) -le $tolerancePx) -and
					([Math]::Abs($window.Width - $target.Width) -le $tolerancePx) -and
					([Math]::Abs($window.Height - $target.Height) -le $tolerancePx)

				if ($holds) {
					# A window whose own verification gave up may still have settled on its bounds.
					if ($record.Category -ne 'Centered') {
						& $recordOutcome $window.Handle 'Centered' $record.Label $target
					}
					continue
				}

				$stragglers += @{ Window = $window; Target = $target; IsNew = $false }
			}

			if ($stragglers.Count -eq 0) {
				Write-LogDebug "     Convergence round ${round}: every window holds its centered bounds" -Style Success
				break
			}

			foreach ($straggler in $stragglers) {
				$window = $straggler.Window
				$target = $straggler.Target
				$title = $window.Title
				$procName = $window.ProcessName
				$observedText = "($($window.Left), $($window.Top)) [$($window.Width)x$($window.Height)]"

				if ($straggler.IsNew) {
					$totalEligibleWindows++
					$label = Get-WindowDisplayName -ProcessName $procName -Title $title
					Write-LogDebug "     ! [$title] ($procName) appeared in convergence round $round - centering it" -Style Warning
				}
				else {
					$label = $outcomes[[string]$window.Handle].Label
					if ($isFinalRound) {
						& $recordOutcome $window.Handle 'Failed' $label $target
						Write-LogDebug "     ✗ [$title] ($procName) is still at $observedText after round $round instead of ($($target.X), $($target.Y)) [$($target.Width)x$($target.Height)]" -Style Warning
						continue
					}
					Write-LogDebug "     ! [$title] ($procName) moved to $observedText after round $round - re-centering" -Style Warning
				}

				$placement = & $placeWindow $window.Handle $title $procName $target
				if ($placement.Placed) {
					& $recordOutcome $window.Handle 'Centered' $label $target
					Write-LogDebug "     ✓ Re-centered [$title] ($procName) => ($($target.X), $($target.Y)) [$($target.Width)x$($target.Height)]" -Style Success
				}
				else {
					& $recordOutcome $window.Handle 'Failed' $label $target
					Write-LogDebug "     ✗ Failed to re-center [$title] ($procName)" -Style Warning
				}
			}
		}

		# Derive the summary from the outcome records.
		$centeredCount = 0
		$centeredLabels = @()
		$skippedCount = 0
		$skippedLabels = @()
		foreach ($key in $outcomeOrder) {
			$outcome = $outcomes[$key]
			if ($outcome.Category -eq 'Centered') {
				$centeredCount++
				$centeredLabels += $outcome.Label
			}
			else {
				$skippedCount++
				$skippedLabels += $outcome.Label
			}
		}

		if (Test-LogVerbose) {
			$summary = "Centered [$centeredCount] window(s)"
			if ($skippedCount -gt 0) { $summary += ", skipped [$skippedCount]" }
			$summary += ", enumerated [$totalEnumeratedWindows], eligible [$totalEligibleWindows]"
			if ($excludedTitleCount -gt 0 -or $excludedInvalidSizeCount -gt 0) {
				$summary += ", excluded title [$excludedTitleCount], excluded invalid-size [$excludedInvalidSizeCount]"
			}
			Write-LogDebug $summary
		}
		else {
			Write-LogSuccess "Centered $centeredCount window(s)!"
			Write-LogList -Items $centeredLabels
			# Failures are reported in normal mode too: a pass that silently left windows where
			# they were looked identical to a complete one.
			if ($skippedCount -gt 0) {
				Write-LogWarning "$skippedCount window(s) could not be centered."
				Write-LogList -Items $skippedLabels
			}
		}
	}
}
