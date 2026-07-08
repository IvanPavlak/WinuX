function Center-Windows {
	<#
	.SYNOPSIS
		Centers all open windows on their respective monitors.

	.DESCRIPTION
		Enumerates all visible application windows, determines which monitor each
		window is currently on (based on its center point), then moves and resizes
		every window to a centered position within that monitor's work area.

		By default, windows are resized to 40% of the monitor work area width and
		50% of the height. Use -WidthPercent and -HeightPercent to customize.

		Filtering mirrors Move-Windows: pass -ProcessName and/or -WindowTitle to
		center only matching windows (exact, wildcard, and regex, with OR logic when
		both are provided), delegated to Get-WindowHandle. When neither is supplied,
		all visible application windows are centered.

		The actual move/resize is delegated to Resize-Windows in target-bounds mode
		(with -InsetPercent 0 for exact placement), so window placement flows through
		a single source of truth (DRY) shared with the layout/snap pipeline.

		Uses existing module functions:
		- Get-WindowHandle for pattern-based window filtering (wildcard, regex, exact)
		- Get-CachedWindows for fast window enumeration (when no filters)
		- Get-MonitorInfo for monitor bounds and work areas
		- Resize-Windows for reliable, centralized window placement
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
		monitor it already lives on.

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
	#>
	[CmdletBinding()]
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

		[Parameter()]
		[switch]$OnPrimary
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

		# When -OnPrimary is set, resolve the primary monitor once and force every
		# matched window onto it, regardless of which monitor it currently lives on.
		$forcedMonitor = $null
		if ($OnPrimary) {
			$forcedMonitor = $monitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
			if (-not $forcedMonitor) {
				$forcedMonitor = $monitors[0]
			}
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

		$centeredCount = 0
		$centeredLabels = @()
		$skippedCount = 0
		$excludedTitleCount = 0
		$excludedInvalidSizeCount = 0
		$totalEnumeratedWindows = @($allWindows).Count
		$totalEligibleWindows = 0

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

			# Determine the target monitor. With -OnPrimary every window is forced
			# onto the primary monitor; otherwise pick the monitor the window is
			# currently on based on its center point.
			if ($forcedMonitor) {
				$targetMonitor = $forcedMonitor
			}
			else {
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

					Write-LogDebug "  [$title] is off-screen, moving to primary monitor!" -Style Warning
				}
			}

			# Calculate centered position within the monitor's work area
			$newWidth = [math]::Floor($targetMonitor.WorkAreaWidth * $WidthPercent / 100)
			$newHeight = [math]::Floor($targetMonitor.WorkAreaHeight * $HeightPercent / 100)
			$newX = $targetMonitor.WorkAreaLeft + [math]::Floor(($targetMonitor.WorkAreaWidth - $newWidth) / 2)
			$newY = $targetMonitor.WorkAreaTop + [math]::Floor(($targetMonitor.WorkAreaHeight - $newHeight) / 2)

			# Delegate the actual move/resize to Resize-Windows in target-bounds mode.
			# InsetPercent 0 places the window at the exact centered bounds (no FancyZones inset),
			# keeping all placement on the shared Resize-Windows path (DRY).
			$null = Resize-Windows -WindowHandle $handle -TargetX $newX -TargetY $newY -TargetWidth $newWidth -TargetHeight $newHeight -InsetPercent 0
			$resizeResult = $script:LastResizeWindowsResult

			if ($resizeResult -and $resizeResult.ResizedCount -gt 0) {
				$centeredCount++
				$centeredLabels += Get-WindowDisplayName -ProcessName $procName -Title $title
				Write-LogDebug "     ✓ Centered [$title] ($procName) => ($newX, $newY) [${newWidth}x${newHeight}]" -Style Success
			}
			else {
				$skippedCount++
				Write-LogDebug "     ✗ Failed to center [$title] ($procName)" -Style Warning
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
		}
	}
}
