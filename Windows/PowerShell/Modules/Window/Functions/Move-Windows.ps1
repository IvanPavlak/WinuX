function Move-Windows {
	<#
	.SYNOPSIS
		Moves all open windows to a specified virtual desktop and optional monitor.

	.DESCRIPTION
		Enumerates all visible application windows and moves each one to the
		specified virtual desktop. Uses 1-based indexing for the user-facing
		parameter (desktop 1 is the first desktop). If the target virtual
		desktop does not exist, it is created automatically. After the move
		pass completes, switches focus to the target desktop.

		Optionally, windows can also be moved to a target physical monitor in
		the same pass by using -Monitor. Monitor targeting supports:
		- 1-based monitor index (for example: 1, 2)
		- Standard labels from Get-MonitorSpecs (Primary, Secondary, Monitor3...)
		- Exact monitor device name (for example: \\.\DISPLAY1)

		When monitor targeting is enabled, window position is preserved relative
		to the source monitor work area and then clamped to the destination
		monitor work area for safe placement. Each placement is verified with
		Wait-WindowRect and re-applied once when the window did not land on the
		target monitor, because SetWindowPos reports success for the call even
		when an external window manager moves the window straight back.

		Windows that could not be moved, or that would not stay on the target
		monitor, are reported in normal mode as well as under verbose logging.

		After the per-window pass, up to three convergence rounds re-enumerate
		the windows fresh and re-check every eligible one against the target
		desktop, retrying each straggler at most twice across rounds. The
		per-window verify answers "did this move land right now", not "is every
		window there after the whole pass": a stale already-on-desktop read taken
		while a desktop collapse was still settling, the upstream Move-Window
		moving a sibling window of the same multi-window process (its fallback
		when the requested view cannot be moved), or a window that had no title
		yet (and so was not enumerated) while it loaded, all leave a window
		elsewhere while the first pass believed otherwise. Re-enumerating rather
		than re-checking the first pass's list is what catches the last case. The
		loop ends as soon as a round finds nothing off the target; a window it
		cannot recover is reported as a failure so the summary never shows a
		clean pass over a straggler.

		Use -Current to move windows to the same virtual desktop as the
		calling terminal, without needing to know which desktop number it is.

		Filtering supports ProcessName and/or WindowTitle with exact names,
		wildcard patterns (*, ?), and regex - delegated to Get-WindowHandle.
		When both are provided, windows matching EITHER criterion are moved
		(OR logic), consistent with Get-WindowHandle conventions.

		Uses existing module functions:
		- Get-WindowHandle for pattern-based window filtering (wildcard, regex, exact)
		- Get-CachedWindows for fast window enumeration (when no filters)
		- Move-WindowToVirtualDesktop for reliable virtual desktop placement
		- Get-WindowDesktopIndex for the post-pass verification sweep
		- Resolve-TargetMonitor for -Monitor resolution (index, label, device name)
		- Wait-WindowRect for post-placement verification of the monitor move
		- Import-VirtualDesktopModule for VirtualDesktop module availability

	.PARAMETER VirtualDesktop
		The virtual desktop number to move all windows to (1-based).
		Desktop 1 is the first desktop. Default is 1.
		Cannot be used together with -Current.

	.PARAMETER Current
		Moves windows to the virtual desktop where the calling terminal
		session is currently located. Detects the active desktop automatically.
		Cannot be used together with -VirtualDesktop.

	.PARAMETER ProcessName
		Optional. Only move windows belonging to processes matching this pattern (without .exe).
		Supports exact names, wildcard patterns (*, ?), and regex.
		Can be used alone or combined with WindowTitle (OR logic).
		When omitted (and no WindowTitle), all visible application windows are moved.

	.PARAMETER WindowTitle
		Optional. Only move windows whose title matches this pattern.
		Supports wildcard patterns (*, ?) and regex.
		Can be used alone or combined with ProcessName (OR logic).
		When omitted (and no ProcessName), all visible application windows are moved.

	.PARAMETER Monitor
		Optional. Also move windows to a target physical monitor.
		Accepted values:
		- 1-based monitor index (for example: 1, 2)
		- Monitor labels (Primary, Secondary, Monitor3, ...)
		- Exact monitor device name (for example: \\.\DISPLAY1)

	.EXAMPLE
		Move-Windows
		Moves all windows to the first virtual desktop.

	.EXAMPLE
		Move-Windows -VirtualDesktop 2
		Moves all windows to the second virtual desktop.

	.EXAMPLE
		Move-Windows -Current
		Moves all windows to the same virtual desktop as the calling terminal
		(and keeps focus there).

	.EXAMPLE
		Move-Windows -Current -ProcessName "chrome"
		Moves only Chrome windows to the current terminal's virtual desktop.

	.EXAMPLE
		Move-Windows -VirtualDesktop 3 -ProcessName "chrome"
		Moves only Chrome windows to the third virtual desktop.

	.EXAMPLE
		Move-Windows -ProcessName "(chrome|firefox|msedge)"
		Moves all browser windows to the first virtual desktop (regex match).

	.EXAMPLE
		Move-Windows -WindowTitle "*YouTube*"
		Moves windows with "YouTube" in the title to the first virtual desktop.

	.EXAMPLE
		Move-Windows -WindowTitle "^Visual Studio"
		Moves windows whose title starts with "Visual Studio" (regex match).

	.EXAMPLE
		Move-Windows -ProcessName "chrome" -WindowTitle "*GitHub*"
		Moves Chrome windows OR windows with "GitHub" in the title (OR logic).

	.EXAMPLE
		Move-Windows -Current -Monitor Secondary
		Moves all windows to the current desktop and repositions them on the
		Secondary monitor.

	.EXAMPLE
		Move-Windows -VirtualDesktop 2 -Monitor 1
		Moves all windows to Virtual Desktop 2 and onto monitor index 1.
	#>
	[CmdletBinding(DefaultParameterSetName = 'ByNumber')]
	param (
		[Parameter(ParameterSetName = 'ByNumber')]
		[ValidateRange(1, 100)]
		[int]$VirtualDesktop = 1,

		[Parameter(ParameterSetName = 'ByCurrent')]
		[switch]$Current,

		[Parameter()]
		[string]$ProcessName,

		[Parameter()]
		[string]$WindowTitle,

		[Parameter()]
		[string]$Monitor
	)

	begin {
		$abortProcessing = $false
		# Desktop-manager reads go through the Window module's adapter (Get-CurrentVirtualDesktopIndex,
		# Get-VirtualDesktopCount, Get-WindowDesktopIndex, Switch-VirtualDesktop), which reconnects a
		# stale COM session and retries RPC failures itself. The window move keeps a plain retry.
		$moveMaxAttempts = 3
		$moveInitialDelayMs = 200
		$useRetry = [bool](Get-Command Invoke-WithRetry -ErrorAction SilentlyContinue)

		if ($Current) {
			# Detect the virtual desktop of the calling terminal
			if (-not (Import-VirtualDesktopModule)) {
				Write-LogError "Error: VirtualDesktop module is required for -Current!"
				$abortProcessing = $true
				return
			}

			try {
				$desktopIndex = Get-CurrentVirtualDesktopIndex
				$VirtualDesktop = $desktopIndex + 1
			}
			catch {
				Write-LogError "Error: Could not detect current virtual desktop: $($_.Exception.Message)"
				$abortProcessing = $true
				return
			}

			Write-LogDebug "Current terminal is on Virtual Desktop $VirtualDesktop"
		}
		else {
			# Ensure the VirtualDesktop module is available
			if (-not (Import-VirtualDesktopModule)) {
				Write-LogError "Error: VirtualDesktop module is required!"
				$abortProcessing = $true
				return
			}

			# Create the target virtual desktop if it doesn't exist
			try {
				$desktopCount = Get-VirtualDesktopCount
			}
			catch {
				Write-LogError "Error: Could not query virtual desktops: $($_.Exception.Message)"
				$abortProcessing = $true
				return
			}

			if ($VirtualDesktop -gt $desktopCount) {
				Write-LogDebug "Virtual Desktop $VirtualDesktop does not exist (only $desktopCount desktop(s) available). Creating..." -Style Warning
				$ensured = Ensure-VirtualDesktops -Count $VirtualDesktop
				if ($ensured -eq $false) {
					Write-LogError "Error: Failed to create Virtual Desktop $VirtualDesktop!"
					$abortProcessing = $true
					return
				}
			}

			# Convert 1-based user input to 0-based internal index
			$desktopIndex = $VirtualDesktop - 1
		}

		$targetMonitor = $null
		$monitorTargetLabel = $null
		$allMonitors = $null

		if ($Monitor) {
			# Monitor matching (index / label / device name) lives in Resolve-TargetMonitor so
			# Move-Windows and Center-Windows share one set of rules.
			$allMonitors = Get-MonitorInfo -Quiet
			$resolvedMonitor = Resolve-TargetMonitor -Monitor $Monitor -MonitorInfo $allMonitors

			if (-not $resolvedMonitor.Monitor) {
				Write-LogError $resolvedMonitor.ErrorMessage
				$abortProcessing = $true
				return
			}

			$targetMonitor = $resolvedMonitor.Monitor
			$monitorTargetLabel = $resolvedMonitor.Label

			Write-LogDebug "Target monitor resolved => $monitorTargetLabel ($($targetMonitor.DeviceName))"
		}
	}

	process {
		if ($abortProcessing) {
			return
		}

		if (Test-LogVerbose) {
			$targetText = if ($targetMonitor) {
				"Virtual Desktop $VirtualDesktop and monitor $monitorTargetLabel"
			}
			else {
				"Virtual Desktop $VirtualDesktop"
			}
			# Only call it "All Windows" when no filter narrows the set; otherwise just "Windows".
			$scopeText = if ($ProcessName -or $WindowTitle) { "Windows" } else { "All Windows" }
			Write-LogDebug "Moving $scopeText to $targetText"
		}

		# Clear cache first to get fresh window positions
		Clear-WindowCache

		# Delegate filtering to Get-WindowHandle (supports exact, wildcard, and regex
		# for both ProcessName and WindowTitle with OR logic when both are provided)
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

		# One record per eligible window, keyed by handle: Category is 'Moved', 'Already' or
		# 'Failed' and is overwritten as the convergence rounds below learn more. The summary is
		# derived from this map at the end, so a window recovered (or lost) after the first pass
		# never needs a counter decremented by hand. $outcomeOrder keeps first-seen order for the
		# printed lists.
		$outcomes = @{}
		$outcomeOrder = [System.Collections.Generic.List[string]]::new()
		$recordOutcome = {
			param($Handle, $Category, $Label, $Title, $ProcessName)
			$key = [string]$Handle
			if (-not $outcomes.ContainsKey($key)) { $outcomeOrder.Add($key) }
			$outcomes[$key] = @{ Category = $Category; Label = $Label; Title = $Title; ProcessName = $ProcessName }
		}

		$monitorMovedCount = 0
		$monitorSkippedCount = 0
		$monitorSkippedLabels = @()
		$excludedTitleCount = 0
		$excludedInvalidSizeCount = 0
		$totalEnumeratedWindows = @($allWindows).Count
		$totalEligibleWindows = 0

		# Monitor placement is verified and re-applied rather than trusted: an external window
		# manager can pull a window back to another monitor immediately after the move while
		# SetWindowPos still reports success. Two attempts with a short verification budget keep
		# the worst case bounded for a full-desktop pass.
		$monitorPlacementAttempts = 2
		$monitorVerifyTimeoutMs = 150

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

			# Check if the window is already on the target desktop
			# -1 (desktop cannot be determined) never equals the target, so the move proceeds.
			$isAlreadyOnDesktop = $false
			$windowDesktopIndex = Get-WindowDesktopIndex -WindowHandle $handle
			if ($windowDesktopIndex -eq $desktopIndex) {
				$isAlreadyOnDesktop = $true
				if (-not $targetMonitor) {
					& $recordOutcome $handle 'Already' (Get-WindowDisplayName -ProcessName $procName -Title $title) $title $procName
					Write-LogDebug "     ○ [$title] ($procName) is already on Virtual Desktop $VirtualDesktop" -Style Warning
					continue
				}
			}

			$result = $true
			if (-not $isAlreadyOnDesktop) {
				# Move window to the target virtual desktop
				$moveErr = $null
				$moveFailureMessage = ''
				try {
					$moveAction = {
						$localMoveErr = $null
						$localResult = Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber $desktopIndex -ErrorVariable localMoveErr -ErrorAction SilentlyContinue
						if (-not $localResult) {
							if ($localMoveErr) {
								throw $localMoveErr[0].Exception.Message
							}
							throw "Move-WindowToVirtualDesktop returned no result"
						}
						return $true
					}

					$result = if ($useRetry) {
						Invoke-WithRetry -ScriptBlock $moveAction -MaxAttempts $moveMaxAttempts -InitialDelayMs $moveInitialDelayMs
					}
					else {
						& $moveAction
					}
				}
				catch {
					$result = $false
					$moveFailureMessage = $_.Exception.Message
				}

				if ($result) {
					& $recordOutcome $handle 'Moved' (Get-WindowDisplayName -ProcessName $procName -Title $title) $title $procName
					Write-LogDebug "     ✓ Moved [$title] ($procName) => Virtual Desktop $VirtualDesktop" -Style Success
				}
				else {
					# Recorded as failed for now; the convergence rounds below get another go at it.
					& $recordOutcome $handle 'Failed' (Get-WindowDisplayName -ProcessName $procName -Title $title) $title $procName
					$reason = if ($moveFailureMessage) { ": $moveFailureMessage" } elseif ($moveErr) { ": $($moveErr[0].Exception.Message)" } else { '' }
					Write-LogDebug "     ✗ Failed to move [$title] ($procName)$reason" -Style Warning
					continue
				}
			}
			else {
				& $recordOutcome $handle 'Already' (Get-WindowDisplayName -ProcessName $procName -Title $title) $title $procName
				Write-LogDebug "     ○ [$title] ($procName) is already on Virtual Desktop $VirtualDesktop" -Style Warning
			}

			if ($targetMonitor) {
				# Preserve relative placement from source monitor work area and clamp
				# to destination work area to support different monitor sizes.
				$windowCenterX = $window.Left + [math]::Floor($window.Width / 2)
				$windowCenterY = $window.Top + [math]::Floor($window.Height / 2)

				$sourceMonitor = $allMonitors | Where-Object {
					$windowCenterX -ge $_.Left -and $windowCenterX -lt $_.Right -and
					$windowCenterY -ge $_.Top -and $windowCenterY -lt $_.Bottom
				} | Select-Object -First 1

				if (-not $sourceMonitor) {
					$sourceMonitor = $allMonitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
					if (-not $sourceMonitor) {
						$sourceMonitor = $allMonitors[0]
					}
				}

				$maxSourceXSpan = [math]::Max(1, $sourceMonitor.WorkAreaWidth - $window.Width)
				$maxSourceYSpan = [math]::Max(1, $sourceMonitor.WorkAreaHeight - $window.Height)

				# The clamp literals MUST be doubles. With int literals PowerShell binds the
				# [math]::Min(int, int) / [math]::Max(int, int) overloads and rounds the relative
				# fraction to 0 or 1, which slams every window into a corner of the destination
				# work area instead of preserving its relative placement.
				$relativeX = [double](($window.Left - $sourceMonitor.WorkAreaLeft) / $maxSourceXSpan)
				$relativeY = [double](($window.Top - $sourceMonitor.WorkAreaTop) / $maxSourceYSpan)
				$relativeX = [math]::Max(0.0, [math]::Min(1.0, $relativeX))
				$relativeY = [math]::Max(0.0, [math]::Min(1.0, $relativeY))

				$newWidth = [math]::Min($window.Width, $targetMonitor.WorkAreaWidth)
				$newHeight = [math]::Min($window.Height, $targetMonitor.WorkAreaHeight)
				$targetXSpan = [math]::Max(0, $targetMonitor.WorkAreaWidth - $newWidth)
				$targetYSpan = [math]::Max(0, $targetMonitor.WorkAreaHeight - $newHeight)

				$newX = $targetMonitor.WorkAreaLeft + [math]::Round($relativeX * $targetXSpan)
				$newY = $targetMonitor.WorkAreaTop + [math]::Round($relativeY * $targetYSpan)

				$maxX = $targetMonitor.WorkAreaLeft + $targetXSpan
				$maxY = $targetMonitor.WorkAreaTop + $targetYSpan
				$newX = [math]::Max($targetMonitor.WorkAreaLeft, [math]::Min($maxX, $newX))
				$newY = [math]::Max($targetMonitor.WorkAreaTop, [math]::Min($maxY, $newY))

				# Verify the window actually landed on the target monitor instead of trusting
				# SetWindowPos' return value, and re-apply when it did not. SetWindowPos reports
				# success for the CALL; an external window manager (for example FancyZones with
				# "keep windows in their zones" enabled) can move the window back to a remembered
				# zone on another monitor right afterwards. Wait-WindowRect is the same
				# verification the snap pipeline uses.
				$monitorMoveResult = $false
				$lastObserved = $null

				for ($placementAttempt = 1; $placementAttempt -le $monitorPlacementAttempts; $placementAttempt++) {
					if (-not (Set-WindowPosition -WindowHandle $handle -X $newX -Y $newY -Width $newWidth -Height $newHeight)) {
						continue
					}

					$placementCheck = Wait-WindowRect -WindowHandle $handle `
						-ExpectedX $newX -ExpectedY $newY `
						-ExpectedWidth $newWidth -ExpectedHeight $newHeight `
						-TimeoutMs $monitorVerifyTimeoutMs

					if ($placementCheck.Verified) {
						$monitorMoveResult = $true
						break
					}

					$lastObserved = $placementCheck
					Write-LogDebug "     ! [$title] ($procName) did not hold monitor $monitorTargetLabel on attempt $placementAttempt (observed $($placementCheck.X), $($placementCheck.Y))" -Style Warning
				}

				if ($monitorMoveResult) {
					$monitorMovedCount++
					Write-LogDebug "     ✓ Repositioned [$title] ($procName) => monitor $monitorTargetLabel" -Style Success
				}
				else {
					$monitorSkippedCount++
					$monitorSkippedLabels += Get-WindowDisplayName -ProcessName $procName -Title $title
					$observedText = if ($lastObserved) { " (last observed $($lastObserved.X), $($lastObserved.Y))" } else { '' }
					Write-LogDebug "     ✗ Failed to reposition [$title] ($procName) on monitor $monitorTargetLabel$observedText" -Style Warning
				}
			}
		}

		# Convergence rounds: the in-loop verify answers "did this move land right now", not "is
		# every window on the target once the whole pass has run". A stale already-on-desktop read
		# taken while desktop-collapse migrations were still settling, a verify race inside
		# Move-WindowToVirtualDesktop, or the upstream Move-Window moving a sibling window of the
		# same multi-window process (its documented fallback when the requested view cannot be
		# moved) all leave a window elsewhere while the records say otherwise. Each round
		# re-enumerates the windows FRESH instead of re-checking only the ones the pass saw: a
		# window that had no title yet while it loaded, or that Windows was still migrating off a
		# collapsing desktop, was not in the first enumeration at all and would otherwise never be
		# looked at. Every window found off the target is retried, at most $maxRetriesPerWindow
		# times across rounds, and the loop ends as soon as a round finds nothing left to do (or
		# every remaining straggler has spent its retries). What still fails is recorded as such,
		# so the summary reports it instead of showing a clean pass.
		$convergenceRounds = 3
		$maxRetriesPerWindow = 2
		$roundSettleMs = 150
		$retryCounts = @{}

		for ($round = 1; $round -le $convergenceRounds; $round++) {
			Clear-WindowCache
			$roundWindows = if ($hasFilter) { Get-WindowHandle @filterParams } else { Get-CachedWindows }

			$stragglers = @()
			foreach ($window in @($roundWindows)) {
				if ($window.Title -in $skipTitles) { continue }
				if ($window.Width -le 0 -or $window.Height -le 0) { continue }

				try {
					$roundIndex = Get-WindowDesktopIndex -WindowHandle $window.Handle
				}
				catch {
					continue
				}
				# -1 means "cannot tell" (pinned/system window, window closed mid-pass) - leave it be.
				if ($roundIndex -lt 0 -or $roundIndex -eq $desktopIndex) { continue }

				$stragglers += @{ Window = $window; Index = $roundIndex }
			}

			if ($stragglers.Count -eq 0) {
				Write-LogDebug "     Convergence round ${round}: every window is on Virtual Desktop $VirtualDesktop" -Style Success
				break
			}

			$retriedAny = $false
			foreach ($straggler in $stragglers) {
				$window = $straggler.Window
				$key = [string]$window.Handle
				$label = if ($outcomes.ContainsKey($key)) { $outcomes[$key].Label } else { Get-WindowDisplayName -ProcessName $window.ProcessName -Title $window.Title }

				if (-not $retryCounts.ContainsKey($key)) { $retryCounts[$key] = 0 }
				if ($retryCounts[$key] -ge $maxRetriesPerWindow) {
					# Out of retries: it stays recorded as failed (set below on its last failure).
					continue
				}
				$retryCounts[$key]++
				$retriedAny = $true

				Write-LogDebug "     ! [$($window.Title)] ($($window.ProcessName)) is on Virtual Desktop $($straggler.Index + 1) after round $round - retrying ($($retryCounts[$key])/$maxRetriesPerWindow)" -Style Warning

				$recovered = $false
				try {
					$recovered = [bool](Move-WindowToVirtualDesktop -WindowHandle $window.Handle -DesktopNumber $desktopIndex -ErrorAction SilentlyContinue)
				}
				catch {
					$recovered = $false
				}

				if ($recovered) {
					# Whatever the first pass believed ('Already' from a stale read, 'Failed' from a
					# transient error, or not seen at all), the window is on the target now and got
					# there because this pass moved it.
					& $recordOutcome $window.Handle 'Moved' $label $window.Title $window.ProcessName
					Write-LogDebug "     ✓ Recovered [$($window.Title)] ($($window.ProcessName)) => Virtual Desktop $VirtualDesktop" -Style Success
				}
				else {
					& $recordOutcome $window.Handle 'Failed' $label $window.Title $window.ProcessName
					Write-LogDebug "     ✗ [$($window.Title)] ($($window.ProcessName)) could not be brought to Virtual Desktop $VirtualDesktop" -Style Warning
				}
			}

			# Nothing left that may still be retried - another round could only re-read the same state.
			if (-not $retriedAny) { break }

			Start-Sleep -Milliseconds $roundSettleMs
		}

		# Derive the summary from the outcome records.
		$movedCount = 0
		$movedLabels = [System.Collections.Generic.List[string]]::new()
		$alreadyCount = 0
		$skippedCount = 0
		$skippedLabels = @()
		foreach ($key in $outcomeOrder) {
			$outcome = $outcomes[$key]
			switch ($outcome.Category) {
				'Moved' { $movedCount++; $movedLabels.Add($outcome.Label) }
				'Already' { $alreadyCount++ }
				'Failed' { $skippedCount++; $skippedLabels += $outcome.Label }
			}
		}

		# Ensure focus follows the destination desktop after window moves complete
		$switchedDesktop = $false
		try {
			$switchedDesktop = [bool](Switch-VirtualDesktop -Index $desktopIndex)
		}
		catch {
			Write-LogDebug "     ! Could not switch focus to Virtual Desktop ${VirtualDesktop}: $($_.Exception.Message)" -Style Warning
		}

		if (Test-LogVerbose) {
			$summary = "Moved [$movedCount] window(s) to Virtual Desktop $VirtualDesktop"
			if ($alreadyCount -gt 0) { $summary += ", already there [$alreadyCount]" }
			if ($skippedCount -gt 0) { $summary += ", skipped [$skippedCount]" }
			$summary += ", enumerated [$totalEnumeratedWindows], eligible [$totalEligibleWindows]"
			if ($excludedTitleCount -gt 0 -or $excludedInvalidSizeCount -gt 0) {
				$summary += ", excluded title [$excludedTitleCount], excluded invalid-size [$excludedInvalidSizeCount]"
			}
			if ($targetMonitor) {
				$summary += ", monitor moved [$monitorMovedCount]"
				if ($monitorSkippedCount -gt 0) { $summary += ", monitor failed [$monitorSkippedCount]" }
			}
			if ($switchedDesktop) { $summary += ", focused desktop [$VirtualDesktop]" }
			Write-LogDebug $summary
		}
		else {
			if ($movedCount -gt 0) {
				Write-LogSuccess "Moved $movedCount window(s) to Virtual Desktop $VirtualDesktop!"
				Write-LogList -Items $movedLabels
			}
			if ($alreadyCount -gt 0) {
				Write-LogWarning "$alreadyCount window(s) already on Virtual Desktop $VirtualDesktop."
			}
			# Failures are reported in normal mode too: silently dropping them made a partial
			# pass look identical to a complete one.
			if ($skippedCount -gt 0) {
				Write-LogWarning "$skippedCount window(s) could not be moved to Virtual Desktop $VirtualDesktop."
				Write-LogList -Items $skippedLabels
			}
			if ($targetMonitor -and $monitorMovedCount -gt 0) {
				Write-LogSuccess "$monitorMovedCount window(s) moved to monitor $monitorTargetLabel."
			}
			if ($targetMonitor -and $monitorSkippedCount -gt 0) {
				Write-LogWarning "$monitorSkippedCount window(s) did not stay on monitor $monitorTargetLabel."
				Write-LogList -Items $monitorSkippedLabels
			}
		}
	}
}
