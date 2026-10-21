function Update-LayoutSectionHeaders {
	<#
	.SYNOPSIS
		Updates the section headers in the Layout array to match the actual desktop numbers.

	.DESCRIPTION
		Parses a PowerShell data file content and regenerates the section headers
		(e.g., "# VIRTUAL DESKTOP 1 - Monitor: Primary - Layout: One") within the
		Layout array based on the actual DesktopNumber, Monitor, and Layout type
		values in the configuration. Layout files use 1-based indexing for DesktopNumber.

		Entries are re-sorted by DesktopNumber, monitor order (Resolve-MonitorLabel), the zone's
		index in ZoneNameMappings, then original position. A pair with no VirtualDesktopLayouts
		entry is headed "Layout: Unknown". Every entry must carry DesktopNumber = <n> and a quoted
		Monitor = "..." (single or double quotes) for the array to be rewritten; when any entry
		lacks either, a warning is logged and the content is returned unchanged rather than
		rewritten without that entry. Single-line entries (@{ ... } on one line) are read as
		entries of their own.

		Only the base Layout array is rewritten. A ProjectOverrides block after it (project
		variants of the layout, see Merge-LayoutProjectOverrides) is carried over verbatim.

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

	# A ProjectOverrides block follows the base Layout array and holds Layout arrays of its own;
	# only the text before it is the base layout this function rewrites. The block is split off
	# here and appended unchanged.
	$projectOverridesTail = ''
	$projectOverridesMatch = [regex]::Match($Content, '(?m)^[ \t]*ProjectOverrides\s*=')
	if ($projectOverridesMatch.Success) {
		$projectOverridesTail = $Content.Substring($projectOverridesMatch.Index)
		$Content = $Content.Substring(0, $projectOverridesMatch.Index)
	}

	$zoneNameMappings = Get-ConfigSetting -Path 'ZoneNameMappings'

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
			# Detect start of an entry. The braces of the opening line itself count, so an entry
			# written on one line closes on that line instead of swallowing the next one.
			if (-not $inEntry -and $line -match '^\s*@\{') {
				$currentEntry = $line
				$braceDepth = ([regex]::Matches($line, '\{')).Count - ([regex]::Matches($line, '\}')).Count
				if ($braceDepth -le 0) {
					$entries += $currentEntry
					$currentEntry = ""
				}
				else {
					$inEntry = $true
				}
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
			if ($entry -match 'Monitor\s*=\s*["'']([^"'']+)["'']') {
				$monitor = $matches[1]
			}
			if ($entry -match 'Zone\s*=\s*["'']([^"'']+)["'']') {
				$zone = $matches[1]
			}

			if ($null -ne $desktopNum -and $null -ne $monitor) {
				$layoutType = & $resolveLayoutType -LayoutConfig $Config -DesktopNumber $desktopNum -MonitorName $monitor
				$entriesWithMetadata += @{
					DesktopNumber = $desktopNum
					Monitor       = $monitor
					# Resolve-MonitorLabel replaces a local Primary=0 / Secondary=1 / everything-else=2
					# mapping under which Monitor3, Monitor4 and Monitor5 all tied at 2 and fell back
					# to input order, making generated headers look randomly ordered past Secondary.
					MonitorSort   = Resolve-MonitorLabel -Label $monitor
					LayoutType    = $layoutType
					Zone          = $zone
					ZoneSort      = & $resolveZoneSortOrder -LayoutType $layoutType -ZoneName $zone
					OriginalIndex = $entryIndex
					Content       = $entry
				}
			}
		}

		# An entry whose desktop or monitor cannot be read from its text has no place in the
		# rebuilt array. Rewriting without it would delete it from the file, so leave the content
		# as it is.
		if ($entriesWithMetadata.Count -ne $entries.Count) {
			Write-LogWarning "Section headers not updated: $($entries.Count - $entriesWithMetadata.Count) layout entry(ies) carry no readable DesktopNumber or Monitor value!"
			return $Content + $projectOverridesTail
		}

		# Group and rebuild with section headers
		$rebuiltLayout = ""
		$lastKey = $null

		# Sort by DesktopNumber first, then by Monitor (Primary, Secondary, Monitor3, Monitor4, ...;
		# unrecognized labels tie at [int]::MaxValue and are broken alphabetically by name)
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
		return $beforeLayout + $rebuiltLayout + "`t" + $afterLayout + $projectOverridesTail
	}

	# If we couldn't parse, return original content
	return $Content + $projectOverridesTail
}
