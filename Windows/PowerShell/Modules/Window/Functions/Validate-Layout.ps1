function Validate-Layout {
	<#
	.SYNOPSIS
		Validates a window layout configuration for consistency.

	.DESCRIPTION
		Validates the VirtualDesktopLayouts configuration and the actual Layout array.
		Layout files use 1-based indexing for DesktopNumber and VirtualDesktopLayouts keys.
		Checks for:
		- Consistency of virtual desktop count across all monitors
		- Contiguous desktop indices (1, 2, 3, ...)
		- Desktop numbers in Layout array within valid range
		- Unused desktop definitions (warning only)

	.PARAMETER Config
		The imported layout configuration hashtable.

	.PARAMETER LayoutName
		Optional name of the layout being validated (for error messages).

	.EXAMPLE
		$config = Import-PowerShellDataFile -Path "Layout.psd1"
		$result = Validate-Layout -Config $config -LayoutName "WinuX_PC"

	.OUTPUTS
		Hashtable with keys:
		- IsValid (bool): Whether validation passed
		- Errors (array): Array of error messages
		- Warnings (array): Array of warning messages
	#>
	param (
		[Parameter(Mandatory = $true)]
		[hashtable]$Config,

		[Parameter(Mandatory = $false)]
		[string]$LayoutName = "Layout"
	)

	$result = @{
		IsValid  = $true
		Errors   = @()
		Warnings = @()
	}

	# Calculate required virtual desktops from Monitors configuration
	# Layout files use 1-based indexing (1, 2, 3, ...) for VirtualDesktopLayouts keys
	$requiredCount = 0
	$monitorDesktopCounts = @{}

	if ($Config.Monitors) {
		foreach ($monitorEntry in $Config.Monitors.GetEnumerator()) {
			$monitorName = $monitorEntry.Key
			$monitorConfig = $monitorEntry.Value

			if ($monitorConfig.VirtualDesktopLayouts) {
				$desktopIndices = @($monitorConfig.VirtualDesktopLayouts.Keys | Sort-Object)
				$actualCount = $desktopIndices.Count
				$minDesktopIndex = ($desktopIndices | Measure-Object -Minimum).Minimum
				$maxDesktopIndex = ($desktopIndices | Measure-Object -Maximum).Maximum
				$desktopCount = $maxDesktopIndex  # 1-based, so max index equals count

				$monitorDesktopCounts[$monitorName] = $desktopCount

				# Track the maximum required count across all monitors
				if ($desktopCount -gt $requiredCount) {
					$requiredCount = $desktopCount
				}

				# Check if indices are contiguous (1, 2, 3, ...) - 1-based indexing
				$expectedIndices = 1..$maxDesktopIndex
				$missingIndices = $expectedIndices | Where-Object { $desktopIndices -notcontains $_ }
				if ($missingIndices.Count -gt 0) {
					$result.Errors += "Monitor '$monitorName': Missing virtual desktop indices: $($missingIndices -join ', ') (expected 1 to $maxDesktopIndex)"
					$result.IsValid = $false
				}

				# Check if indexing starts at 1 (not 0)
				if ($minDesktopIndex -eq 0) {
					$result.Errors += "Monitor '$monitorName': VirtualDesktopLayouts uses 0-based indexing but should use 1-based (start from 1, not 0)"
					$result.IsValid = $false
				}
			}
		}

		# Check if all monitors have the same desktop count
		$uniqueCounts = $monitorDesktopCounts.Values | Select-Object -Unique
		if ($uniqueCounts.Count -gt 1) {
			$result.Warnings += "Monitors have different virtual desktop counts: $(($monitorDesktopCounts.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
		}
	}

	# If no monitors defined or no virtual desktops, return early
	if ($requiredCount -eq 0) {
		return $result
	}

	# Check actual Layout array desktop numbers (1-based indexing)
	if ($Config.Layout) {
		$usedDesktopNumbers = @($Config.Layout | ForEach-Object { $_.DesktopNumber } | Select-Object -Unique | Sort-Object)
		$expectedDesktopNumbers = 1..$requiredCount

		# Check for desktop numbers beyond the required range or below 1
		$outOfRange = $usedDesktopNumbers | Where-Object { $_ -gt $requiredCount -or $_ -lt 1 }
		if ($outOfRange.Count -gt 0) {
			$result.Errors += "Layout array uses invalid desktop numbers: $($outOfRange -join ', ') (valid range: 1 to $requiredCount)"
			$result.IsValid = $false
		}

		# Check for missing desktop numbers (warning, not error)
		$unusedDesktops = $expectedDesktopNumbers | Where-Object { $usedDesktopNumbers -notcontains $_ }
		if ($unusedDesktops.Count -gt 0) {
			$result.Warnings += "Desktop(s) $($unusedDesktops -join ', ') defined in VirtualDesktopLayouts but not used in Layout array"
		}

		# Validate that zone-based layouts can be resolved
		foreach ($item in $Config.Layout) {
			# Only validate items that use zone-based positioning (have a Zone but no explicit Layout)
			if ($item.Zone -and -not $item.Layout) {
				$hasMonitor = $item.Monitor
				$hasDesktop = $null -ne $item.DesktopNumber

				if (-not $hasMonitor) {
					$result.Errors += "Layout item for '$($item.ProcessName)' has Zone='$($item.Zone)' but no Monitor specified"
					$result.IsValid = $false
					continue
				}

				if (-not $hasDesktop) {
					$result.Errors += "Layout item for '$($item.ProcessName)' has Zone='$($item.Zone)' but no DesktopNumber specified"
					$result.IsValid = $false
					continue
				}

				# Check if the Monitor exists in Monitors section
				if (-not $Config.Monitors -or -not $Config.Monitors.ContainsKey($item.Monitor)) {
					$result.Errors += "Layout item for '$($item.ProcessName)' references Monitor='$($item.Monitor)' which is not defined in Monitors section"
					$result.IsValid = $false
					continue
				}

				# Check if the Monitor has VirtualDesktopLayouts
				$monitorConfig = $Config.Monitors[$item.Monitor]
				if (-not $monitorConfig.VirtualDesktopLayouts) {
					$result.Errors += "Layout item for '$($item.ProcessName)' references Monitor='$($item.Monitor)' which has no VirtualDesktopLayouts defined"
					$result.IsValid = $false
					continue
				}

				# Check if the specific desktop is defined for this monitor
				if (-not $monitorConfig.VirtualDesktopLayouts.ContainsKey($item.DesktopNumber)) {
					$result.Errors += "Layout item for '$($item.ProcessName)' references Monitor='$($item.Monitor)' Desktop=$($item.DesktopNumber) but no layout is defined for this combination in Monitors section"
					$result.IsValid = $false
					continue
				}
			}
		}

		# Soft warning: detect legacy hardcoded browser-alternation regex and
		# suggest the `Browser` token instead. Matches strings like
		# "(firefox|chrome|msedge|brave)" or ".*Firefox.*|.*Chrome.*" etc.
		# Non-fatal - existing files continue to work.
		$legacyProcessPattern = '(?i)firefox.*chrome|chrome.*firefox'
		$legacyTitlePattern = '(?i)\.\*\s*Firefox|\.\*\s*Chrome|\.\*\s*Edge|\.\*\s*Brave'
		$legacySeen = $false
		foreach ($item in $Config.Layout) {
			$pn = [string]$item.ProcessName
			$wt = [string]$item.WindowTitle
			if ($pn -and $pn -ne 'Browser' -and $pn -match $legacyProcessPattern) { $legacySeen = $true; break }
			if ($wt -and $wt -ne 'Browser' -and $wt -match $legacyTitlePattern) { $legacySeen = $true; break }
		}
		if ($legacySeen) {
			$result.Warnings += "Layout uses legacy hardcoded browser-alternation regex for ProcessName/WindowTitle. Consider replacing with the 'Browser' token (e.g. ProcessName = 'Browser') - see docs/modules/window.md."
		}
	}

	return $result
}
