function Update-LayoutSectionHeaders {
	<#
	.SYNOPSIS
		Updates the section headers in the Layout array to match the actual desktop numbers.

	.DESCRIPTION
		Parses a PowerShell data file content and regenerates the section headers
		(e.g., "# VIRTUAL DESKTOP 1 - Monitor: Primary - Layout: One") within the
		Layout array based on the actual DesktopNumber, Monitor, and Layout type
		values in the configuration. Layout files use 1-based indexing for DesktopNumber.

	.PARAMETER Content
		The file content without the visualization block.

	.PARAMETER Config
		The parsed configuration object containing the Layout array.

	.EXAMPLE
		$content = Get-Content -Path "layout.psd1" -Raw
		$config = Import-PowerShellDataFile -Path "layout.psd1"
		$updated = Update-LayoutSectionHeaders -Content $content -Config $config
	#>
	param (
		[string]$Content,
		[hashtable]$Config
	)

	$zoneNameMappings = $null
	if ($global:Configuration -and $global:Configuration.ZoneNameMappings) {
		$zoneNameMappings = $global:Configuration.ZoneNameMappings
	}

	$resolveMonitorSortOrder = {
		param (
			[string]$MonitorName
		)

		if ($MonitorName -eq "Primary") { return 0 }
		if ($MonitorName -eq "Secondary") { return 1 }

		return 2
	}

	$resolveLayoutType = {
		param (
			[hashtable]$LayoutConfig,
			[int]$DesktopNumber,
			[string]$MonitorName
		)

		if ($LayoutConfig.Monitors -and
			$LayoutConfig.Monitors.ContainsKey($MonitorName) -and
			$LayoutConfig.Monitors[$MonitorName].VirtualDesktopLayouts -and
			$LayoutConfig.Monitors[$MonitorName].VirtualDesktopLayouts.ContainsKey($DesktopNumber)) {
			return $LayoutConfig.Monitors[$MonitorName].VirtualDesktopLayouts[$DesktopNumber]
		}

		return "Unknown"
	}

	$resolveZoneSortOrder = {
		param (
			[string]$LayoutType,
			[string]$ZoneName
		)

		if ([string]::IsNullOrWhiteSpace($LayoutType) -or
			$LayoutType -eq "Unknown" -or
			[string]::IsNullOrWhiteSpace($ZoneName) -or
			-not $zoneNameMappings -or
			-not $zoneNameMappings.ContainsKey($LayoutType) -or
			-not $zoneNameMappings[$LayoutType].ContainsKey($ZoneName)) {
			return [int]::MaxValue
		}

		return [int]$zoneNameMappings[$LayoutType][$ZoneName]
	}

	# Find the Layout array section in the content
	if ($Content -match '(?s)(.*?Layout\s*=\s*@\(\r?\n?)(.+?)(\)\s*\}?\s*)$') {
		$beforeLayout = $matches[1]
		$layoutContent = $matches[2]
		$afterLayout = $matches[3]

		# Remove all existing section headers
		$layoutContent = $layoutContent -replace '(?m)^\s*#\s*={10,}\s*$\r?\n', ''
		$layoutContent = $layoutContent -replace '(?m)^\s*#\s*VIRTUAL DESKTOP.*$\r?\n', ''

		# Split into individual entries (each @{ ... })
		$entries = @()
		$currentEntry = ""
		$braceDepth = 0
		$inEntry = $false

		foreach ($line in $layoutContent -split '\r?\n') {
			# Detect start of an entry
			if ($line -match '^\s*@\{') {
				$inEntry = $true
				$braceDepth = 1
				$currentEntry = $line
			}
			elseif ($inEntry) {
				$currentEntry += "`n$line"

				# Count braces to determine when entry ends
				$openBraces = ([regex]::Matches($line, '\{')).Count
				$closeBraces = ([regex]::Matches($line, '\}')).Count
				$braceDepth += $openBraces - $closeBraces

				if ($braceDepth -eq 0) {
					# Entry complete
					$entries += $currentEntry
					$currentEntry = ""
					$inEntry = $false
				}
			}
			elseif ($line -match '^\s*$' -or $line -match '^\s*#' -and -not $inEntry) {
				# Skip empty lines and comments between entries (will be regenerated)
				continue
			}
			else {
				# Preserve other content (shouldn't normally happen)
				if ($currentEntry) {
					$entries += $currentEntry
					$currentEntry = ""
				}
			}
		}

		# Add any remaining entry
		if ($currentEntry) {
			$entries += $currentEntry
		}

		# Parse each entry to get its DesktopNumber and Monitor
		$entriesWithMetadata = @()
		for ($entryIndex = 0; $entryIndex -lt $entries.Count; $entryIndex++) {
			$entry = $entries[$entryIndex]
			$desktopNum = $null
			$monitor = $null
			$zone = $null

			if ($entry -match 'DesktopNumber\s*=\s*(\d+)') {
				$desktopNum = [int]$matches[1]
			}
			if ($entry -match 'Monitor\s*=\s*"([^"]+)"') {
				$monitor = $matches[1]
			}
			if ($entry -match 'Zone\s*=\s*"([^"]+)"') {
				$zone = $matches[1]
			}

			if ($null -ne $desktopNum -and $null -ne $monitor) {
				$layoutType = & $resolveLayoutType -LayoutConfig $Config -DesktopNumber $desktopNum -MonitorName $monitor
				$entriesWithMetadata += @{
					DesktopNumber = $desktopNum
					Monitor       = $monitor
					MonitorSort   = & $resolveMonitorSortOrder -MonitorName $monitor
					LayoutType    = $layoutType
					Zone          = $zone
					ZoneSort      = & $resolveZoneSortOrder -LayoutType $layoutType -ZoneName $zone
					OriginalIndex = $entryIndex
					Content       = $entry
				}
			}
		}

		# Group and rebuild with section headers
		$rebuiltLayout = ""
		$lastKey = $null

		# Sort by DesktopNumber first, then by Monitor (Primary first, then Secondary, then others)
		$sortedEntries = $entriesWithMetadata | Sort-Object @(
			@{ Expression = { $_.DesktopNumber }; Ascending = $true }
			@{ Expression = { $_.MonitorSort }; Ascending = $true }
			@{ Expression = { $_.Monitor }; Ascending = $true }
			@{ Expression = { $_.ZoneSort }; Ascending = $true }
			@{ Expression = { $_.OriginalIndex }; Ascending = $true }
		)

		foreach ($entry in $sortedEntries) {
			$desktopNum = $entry.DesktopNumber
			$monitor = $entry.Monitor
			$currentKey = "$desktopNum-$monitor"

			# Add section header if this is a new desktop/monitor combination
			if ($currentKey -ne $lastKey) {
				$layoutType = $entry.LayoutType

				if ($rebuiltLayout) {
					$rebuiltLayout += "`n"
				}
				$rebuiltLayout += "`t`t# " + ("=" * 74) + "`n"
				# DesktopNumber is already 1-based in layout files, display directly
				$rebuiltLayout += "`t`t# VIRTUAL DESKTOP $desktopNum - Monitor: $monitor - Layout: $layoutType`n"
				$rebuiltLayout += "`t`t# " + ("=" * 74) + "`n"
				$lastKey = $currentKey
			}

			$rebuiltLayout += $entry.Content + "`n"
		}

		# Combine everything back together
		return $beforeLayout + $rebuiltLayout + "`t" + $afterLayout
	}

	# If we couldn't parse, return original content
	return $Content
}
