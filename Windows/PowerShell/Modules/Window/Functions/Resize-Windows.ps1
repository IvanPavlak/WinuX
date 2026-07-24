function Resize-Windows {
	<#
	.SYNOPSIS
		Resizes open windows either by a percentage or to inset bounds within a target zone.

	.DESCRIPTION
		Enumerates visible application windows and scales each window's width and
		height by the specified percentage, keeping the window's center point fixed
		so it does not appear to move.

		Like Move-Windows, the target set can be a single window (by handle), a
		filtered set (by ProcessName and/or WindowTitle), or every visible window
		when no filter is supplied:
		- WindowHandle resizes only that specific window.
		- ProcessName and/or WindowTitle delegate to Get-WindowHandle for
		  pattern-based filtering (exact, wildcard, and regex, with OR logic when
		  both are provided), keeping one source of truth for window matching.
		- With neither, all visible application windows are resized.

		A value of 100 leaves windows unchanged. Values below 100 shrink windows,
		and values above 100 enlarge them. The result is clamped to the monitor's
		work area so windows never extend beyond the screen.

		When TargetX, TargetY, TargetWidth, and TargetHeight are provided, the function
		uses the shared FancyZones pre-snap inset sizing logic instead of percentage
		scaling. This keeps Set-WindowLayouts, pre-snap workspace resizing, and
		Snap-AllWindows retries aligned. An InsetPercent of 0 places the window at the
		exact target bounds, which is how Center-Windows reuses this path for centering.

		Uses existing module functions:
		- Get-WindowHandle for pattern-based window filtering (wildcard, regex, exact)
		- Get-CachedWindows for fast window enumeration (when no filters)
		- Get-MonitorInfo for monitor bounds and work areas
		- Get-InsetWindowBounds for the shared target-bounds geometry
		- Set-WindowPosition for reliable window placement
		- Ensure-WindowsFormsLoaded for System.Windows.Forms dependency

	.PARAMETER Percent
		The percentage to scale each window's current size by.
		Default is 70 (shrink to 70% of current size). Range: 10-500.

	.PARAMETER ProcessName
		Optional. Only resize windows belonging to processes matching this pattern (without .exe).
		Supports exact names, wildcard patterns (*, ?), and regex.
		Can be used alone or combined with WindowTitle (OR logic).
		When omitted (and no WindowTitle/WindowHandle), all visible application windows are resized.

	.PARAMETER WindowTitle
		Optional. Only resize windows whose title matches this pattern.
		Supports wildcard patterns (*, ?) and regex.
		Can be used alone or combined with ProcessName (OR logic).
		When omitted (and no ProcessName/WindowHandle), all visible application windows are resized.

	.PARAMETER WindowHandle
		Optional. Only resize the window with this exact handle.

	.PARAMETER TargetX
		Optional. Target zone X coordinate for target-bounds mode.

	.PARAMETER TargetY
		Optional. Target zone Y coordinate for target-bounds mode.

	.PARAMETER TargetWidth
		Optional. Target zone width for target-bounds mode.

	.PARAMETER TargetHeight
		Optional. Target zone height for target-bounds mode.

	.PARAMETER InsetPercent
		Inset percentage applied on each side in target-bounds mode. Default is 0.05.
		Use 0 to place windows at the exact target bounds (no inset).

	.PARAMETER Tolerance
		Pixel tolerance used with SkipIfAlreadyPositioned in target-bounds mode.
		Default is the module's shared position verification tolerance.

	.PARAMETER SkipIfAlreadyPositioned
		Skips resizing when the window is already at the adjusted target bounds within
		the specified Tolerance.

	.EXAMPLE
		Resize-Windows
		Shrinks all windows to 70% of their current size.

	.EXAMPLE
		Resize-Windows -Percent 120
		Enlarges all windows to 120% of their current size.

	.EXAMPLE
		Resize-Windows -Percent 50 -ProcessName "chrome"
		Shrinks only Chrome windows to half their current size.

	.EXAMPLE
		Resize-Windows -Percent 100
		No-op - all windows stay the same size.

	.EXAMPLE
		Resize-Windows -Percent 150 -ProcessName "(chrome|firefox|msedge)"
		Enlarges browser windows to 150% (regex match).

	.EXAMPLE
		Resize-Windows -WindowTitle "*YouTube*" -Percent 120
		Enlarges windows with "YouTube" in the title to 120%.

	.EXAMPLE
		Resize-Windows -WindowHandle $handle
		Shrinks only the specified window to 70% of its current size.

	.EXAMPLE
		Resize-Windows -WindowHandle $handle -TargetX 0 -TargetY 0 -TargetWidth 1720 -TargetHeight 1440 -SkipIfAlreadyPositioned
		Moves the window to the shared inset pre-snap bounds for the target zone.

	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[ValidateRange(10, 500)]
		[int]$Percent = 70,

		[Parameter()]
		[string]$ProcessName,

		[Parameter()]
		[string]$WindowTitle,

		[Parameter()]
		[IntPtr]$WindowHandle,

		[Parameter()]
		[int]$TargetX,

		[Parameter()]
		[int]$TargetY,

		[Parameter()]
		[int]$TargetWidth,

		[Parameter()]
		[int]$TargetHeight,

		[Parameter()]
		[ValidateRange(0.0, 0.49)]
		[double]$InsetPercent = 0.05,

		[Parameter()]
		[int]$Tolerance = $script:WindowModuleTolerances.PositionVerificationPx,

		[Parameter()]
		[switch]$SkipIfAlreadyPositioned
	)

	begin {
		# Ensure Windows Forms is loaded for monitor detection
		Ensure-WindowsFormsLoaded

		$targetBoundParams = @('TargetX', 'TargetY', 'TargetWidth', 'TargetHeight')
		$providedTargetBoundParams = @($targetBoundParams | Where-Object { $PSBoundParameters.ContainsKey($_) })
		$useTargetBoundsMode = $providedTargetBoundParams.Count -gt 0

		if ($useTargetBoundsMode -and $providedTargetBoundParams.Count -ne $targetBoundParams.Count) {
			throw 'Target-bounds mode requires TargetX, TargetY, TargetWidth, and TargetHeight.'
		}
	}

	process {
		# Only the top-level "resize all/matching windows by percent" invocation is user-facing.
		# Target-bounds mode and single-window retries are internal callers (Snap-AllWindows,
		# Set-WindowLayouts, Set-WorkspaceWindowLayout, Center-Windows) that would print this title redundantly.
		if (-not $useTargetBoundsMode -and -not $PSBoundParameters.ContainsKey('WindowHandle')) {
			$scopeText = if ($ProcessName -or $WindowTitle) { "Windows" } else { "All Windows" }
			Write-LogTitle "Resizing $scopeText"
		}

		$script:LastResizeWindowsResult = [PSCustomObject]@{
			ResizedCount  = 0
			SkippedCount  = 0
			FailedWindows = @()
		}

		if (Test-LogVerbose) {
			if ($PSBoundParameters.ContainsKey('WindowHandle')) {
				$resizeTargetLabel = "Target Window [$WindowHandle]"
			}
			elseif ($ProcessName -or $WindowTitle) {
				$resizeTargetLabel = "Matching Windows"
			}
			else {
				$resizeTargetLabel = "All Windows"
			}

			if ($useTargetBoundsMode) {
				Write-LogDebug "Resizing $resizeTargetLabel to Shared Inset Bounds"
			}
			else {
				Write-LogDebug "Resizing $resizeTargetLabel to $Percent%"
			}
		}

		$monitors = $null
		if (-not $useTargetBoundsMode) {
			# Get monitor information using existing cached function
			$monitors = Get-MonitorInfo -Quiet

			if (-not $monitors -or $monitors.Count -eq 0) {
				Write-Warning "`n No monitors detected. Cannot resize windows!"
				return
			}

			if (Test-LogVerbose) {
				Write-LogDebug "Detected $($monitors.Count) monitor(s)!" -Style Step
				foreach ($mon in $monitors) {
					$label = if ($mon.IsPrimary) { "Primary" } else { $mon.DeviceName }
					Write-LogDebug "$label => Work Area ($($mon.WorkAreaLeft), $($mon.WorkAreaTop)) [$($mon.WorkAreaWidth)x$($mon.WorkAreaHeight)]" -Style Step
				}
			}
		}

		# Resolve the target window set.
		# - WindowHandle: a single window (used by internal callers and Center-Windows) -
		#   served from the window cache WITHOUT forcing a refresh. This mode is called once
		#   per window in tight loops (Resize-PositionedWindows, snap retries), and a forced
		#   Clear-WindowCache + re-enumeration per call cost 10-30ms each for data about one
		#   already-known handle; the cache's own 50ms TTL keeps the data fresh enough for
		#   the skip-tolerance check (windows only move when this module moves them).
		# - ProcessName/WindowTitle: delegate filtering to Get-WindowHandle (exact, wildcard,
		#   regex, OR logic) - the same matching path used by Move-Windows. Cache cleared
		#   first for fresh positions.
		# - Neither: all visible windows (cache cleared first).
		if ($PSBoundParameters.ContainsKey('WindowHandle')) {
			$allWindows = @(Get-CachedWindows | Where-Object { $_.Handle -eq $WindowHandle })

			if (-not $allWindows -or $allWindows.Count -eq 0) {
				Write-Warning "`n Window handle [$WindowHandle] was not found. Cannot resize target window!"
				return
			}
		}
		elseif ($ProcessName -or $WindowTitle) {
			Clear-WindowCache
			$filterParams = @{}
			if ($ProcessName) { $filterParams.ProcessName = $ProcessName }
			if ($WindowTitle) { $filterParams.WindowTitle = $WindowTitle }
			$allWindows = Get-WindowHandle @filterParams
		}
		else {
			Clear-WindowCache
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

		$resizedCount = 0
		$skippedCount = 0
		$failedWindows = [System.Collections.Generic.List[object]]::new()

		foreach ($window in $allWindows) {
			$handle = $window.Handle
			$title = $window.Title
			$procName = $window.ProcessName

			# Skip system/shell windows
			if ($title -in $skipTitles) {
				continue
			}

			# Skip windows with no meaningful size (hidden or not real)
			if ($window.Width -le 0 -or $window.Height -le 0) {
				continue
			}

			if ($useTargetBoundsMode) {
				$resizeBounds = Get-InsetWindowBounds -TargetX $TargetX -TargetY $TargetY -TargetWidth $TargetWidth -TargetHeight $TargetHeight -InsetPercent $InsetPercent
				$newX = $resizeBounds.AdjustedX
				$newY = $resizeBounds.AdjustedY
				$newWidth = $resizeBounds.AdjustedWidth
				$newHeight = $resizeBounds.AdjustedHeight

				if ($SkipIfAlreadyPositioned) {
					$xMatch = [Math]::Abs($window.Left - $newX) -le $Tolerance
					$yMatch = [Math]::Abs($window.Top - $newY) -le $Tolerance
					$widthMatch = [Math]::Abs($window.Width - $newWidth) -le $Tolerance
					$heightMatch = [Math]::Abs($window.Height - $newHeight) -le $Tolerance

					if ($xMatch -and $yMatch -and $widthMatch -and $heightMatch) {
						$skippedCount++
						Write-LogDebug "     ↺ [$title] already at shared inset bounds, skipping" -Style Warning
						continue
					}
				}
			}
			else {
				# Determine which monitor this window is on based on its center point
				$windowCenterX = $window.Left + [math]::Floor($window.Width / 2)
				$windowCenterY = $window.Top + [math]::Floor($window.Height / 2)

				$targetMonitor = $null

				foreach ($mon in $monitors) {
					if ($windowCenterX -ge $mon.Left -and $windowCenterX -lt $mon.Right -and
						$windowCenterY -ge $mon.Top -and $windowCenterY -lt $mon.Bottom) {
						$targetMonitor = $mon
						break
					}
				}

				# Fallback: if window center isn't inside any monitor (e.g., off-screen),
				# use the primary monitor
				if (-not $targetMonitor) {
					$targetMonitor = $monitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
					if (-not $targetMonitor) {
						$targetMonitor = $monitors[0]
					}

					Write-LogDebug "  [$title] is off-screen, clamping to primary monitor!" -Style Warning
				}

				# Calculate new size by scaling the current dimensions
				$newWidth = [math]::Floor($window.Width * $Percent / 100)
				$newHeight = [math]::Floor($window.Height * $Percent / 100)

				# Clamp to monitor work area bounds (minimum 100px so windows stay usable)
				$newWidth = [math]::Max(100, [math]::Min($newWidth, $targetMonitor.WorkAreaWidth))
				$newHeight = [math]::Max(100, [math]::Min($newHeight, $targetMonitor.WorkAreaHeight))

				# Keep the window centered on its original center point
				$newX = $windowCenterX - [math]::Floor($newWidth / 2)
				$newY = $windowCenterY - [math]::Floor($newHeight / 2)

				# Clamp position so the window stays within the monitor work area
				$newX = [math]::Max($targetMonitor.WorkAreaLeft, [math]::Min($newX, $targetMonitor.WorkAreaLeft + $targetMonitor.WorkAreaWidth - $newWidth))
				$newY = [math]::Max($targetMonitor.WorkAreaTop, [math]::Min($newY, $targetMonitor.WorkAreaTop + $targetMonitor.WorkAreaHeight - $newHeight))
			}

			if (Test-LogVerbose) {
				if ($useTargetBoundsMode) {
					Write-LogDebug "[$title] ($procName) => target zone ($TargetX, $TargetY) [${TargetWidth}x${TargetHeight}] -> inset ($newX, $newY) [${newWidth}x${newHeight}]" -Style Step
				}
				else {
					Write-LogDebug "[$title] ($procName) => [$($window.Width)x$($window.Height)] -> [${newWidth}x${newHeight}]" -Style Step
				}
			}

			# Use existing Set-WindowPosition for reliable placement
			$result = Set-WindowPosition -WindowHandle $handle -X $newX -Y $newY -Width $newWidth -Height $newHeight

			if ($result) {
				$resizedCount++
				Write-LogDebug "     ✓ Resized [$title] ($procName) => ($newX, $newY) [${newWidth}x${newHeight}]" -Style Success
			}
			else {
				$skippedCount++
				$failedWindows.Add([PSCustomObject]@{
						Handle      = $handle
						WindowTitle = $title
						ProcessName = $procName
						Expected    = if ($useTargetBoundsMode) { "($newX, $newY) ${newWidth}x${newHeight}" } else { $null }
					})
				Write-LogDebug "     ✗ Failed to resize [$title] ($procName)" -Style Warning
			}
		}

		if (Test-LogVerbose) {
			Write-LogDebug "Resized [$resizedCount] window(s)$(if ($skippedCount -gt 0) { ", skipped [$skippedCount]" })"
		}
		elseif (-not $useTargetBoundsMode -and -not $PSBoundParameters.ContainsKey('WindowHandle')) {
			# Only the user-facing "resize all/matching windows" invocation prints a summary.
			# Single-handle percent mode is an internal per-window call (first-open
			# normalization runs it once per new window) - a success line per window spammed
			# the workspace-open output; verbose mode still logs each via the branch above.
			Write-LogSuccess "Resized $resizedCount window(s) to $Percent%!"
		}

		$script:LastResizeWindowsResult = [PSCustomObject]@{
			ResizedCount  = $resizedCount
			SkippedCount  = $skippedCount
			FailedWindows = $failedWindows
		}
	}
}
