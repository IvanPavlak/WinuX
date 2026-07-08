function Get-FancyZoneCoordinates {
	<#
	.SYNOPSIS
		Calculates zone coordinates from FancyZones custom layouts.

	.DESCRIPTION
		Parses the FancyZones custom-layouts.json file and calculates the actual pixel
		coordinates for each zone based on monitor dimensions and layout configuration.

	.PARAMETER LayoutName
		The name of the FancyZones layout (e.g., "Zero", "One", "Seven").

	.PARAMETER MonitorX
		The X position of the monitor (default: 0).

	.PARAMETER MonitorY
		The Y position of the monitor (default: 0).

	.PARAMETER MonitorWidth
		The width of the monitor in pixels (default: 3440).

	.PARAMETER MonitorHeight
		The height of the monitor in pixels (default: 1440).

	.PARAMETER CustomLayoutsPath
		Optional path to custom-layouts.json file. If not specified, uses the default FancyZones location.

	.EXAMPLE
		Get-FancyZoneCoordinates -LayoutName "Seven" -MonitorX 0 -MonitorY -1440 -MonitorWidth 3440 -MonitorHeight 1440

	.EXAMPLE
		$zones = Get-FancyZoneCoordinates -LayoutName "One"
		$leftZone = $zones[0]  # Get coordinates for zone 0 (left)
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$LayoutName,

		[Parameter()]
		[int]$MonitorX = 0,

		[Parameter()]
		[int]$MonitorY = 0,

		[Parameter()]
		[int]$MonitorWidth = 3440,

		[Parameter()]
		[int]$MonitorHeight = 1440,

		[Parameter()]
		[string]$CustomLayoutsPath
	)

	if (-not $CustomLayoutsPath) {
		$CustomLayoutsPath = $global:MachineSpecificPaths.SymbolicLinks.PowerToys.CustomLayouts.Target
	}

	if (-not (Test-Path $CustomLayoutsPath)) {
		Write-Error "Custom layouts file not found: $CustomLayoutsPath"
		return $null
	}

	try {
		# Use cached JSON data to avoid repeated file reads
		$customLayouts = Get-CachedFancyZonesLayouts -LayoutsJsonPath $CustomLayoutsPath
		if ($null -eq $customLayouts) {
			Write-Error "Failed to load custom layouts JSON"
			return $null
		}

		# Find the specified layout
		$layout = $customLayouts.'custom-layouts' | Where-Object { $_.name -eq $LayoutName } | Select-Object -First 1

		if (-not $layout) {
			Write-Error "Layout '$LayoutName' not found in custom layouts file"
			Write-LogStep "Available layouts:" -NoLeadingNewline
			$customLayouts.'custom-layouts' | ForEach-Object {
				Write-LogStep "  - $($_.name)" -NoLeadingNewline
			}
			return $null
		}

		if ($layout.type -ne "grid") {
			Write-Warning "Only grid layouts are currently supported. Layout '$LayoutName' is type '$($layout.type)'"
			return $null
		}

		# Extract layout info
		$rows = $layout.info.rows
		$columns = $layout.info.columns
		$rowPercentages = $layout.info.'rows-percentage'
		$columnPercentages = $layout.info.'columns-percentage'
		$cellChildMap = $layout.info.'cell-child-map'
		$spacing = if ($layout.info.'show-spacing') { $layout.info.spacing } else { 0 }

		# Calculate row and column positions
		$rowPositions = @(0)
		$currentY = 0
		for ($i = 0; $i -lt $rowPercentages.Count; $i++) {
			$rowHeight = [int](($MonitorHeight * $rowPercentages[$i]) / 10000)
			$currentY += $rowHeight
			$rowPositions += $currentY
		}

		$columnPositions = @(0)
		$currentX = 0
		for ($i = 0; $i -lt $columnPercentages.Count; $i++) {
			$columnWidth = [int](($MonitorWidth * $columnPercentages[$i]) / 10000)
			$currentX += $columnWidth
			$columnPositions += $currentX
		}

		# Build a map of zone index to cell ranges
		$zoneMap = @{}
		for ($row = 0; $row -lt $rows; $row++) {
			for ($col = 0; $col -lt $columns; $col++) {
				$zoneIndex = $cellChildMap[$row][$col]

				if (-not $zoneMap.ContainsKey($zoneIndex)) {
					$zoneMap[$zoneIndex] = @{
						MinRow = $row
						MaxRow = $row
						MinCol = $col
						MaxCol = $col
					}
				}
				else {
					if ($row -lt $zoneMap[$zoneIndex].MinRow) { $zoneMap[$zoneIndex].MinRow = $row }
					if ($row -gt $zoneMap[$zoneIndex].MaxRow) { $zoneMap[$zoneIndex].MaxRow = $row }
					if ($col -lt $zoneMap[$zoneIndex].MinCol) { $zoneMap[$zoneIndex].MinCol = $col }
					if ($col -gt $zoneMap[$zoneIndex].MaxCol) { $zoneMap[$zoneIndex].MaxCol = $col }
				}
			}
		}

		# Calculate zone coordinates
		$zones = @()
		foreach ($zoneIndex in ($zoneMap.Keys | Sort-Object)) {
			$zone = $zoneMap[$zoneIndex]

			$zoneX = $MonitorX + $columnPositions[$zone.MinCol]
			$zoneY = $MonitorY + $rowPositions[$zone.MinRow]
			$zoneWidth = $columnPositions[$zone.MaxCol + 1] - $columnPositions[$zone.MinCol]
			$zoneHeight = $rowPositions[$zone.MaxRow + 1] - $rowPositions[$zone.MinRow]

			# Adjust for spacing
			if ($spacing -gt 0) {
				# Add half spacing to X and Y, subtract full spacing from width and height
				$zoneX += [int]($spacing / 2)
				$zoneY += [int]($spacing / 2)
				$zoneWidth -= $spacing
				$zoneHeight -= $spacing
			}

			$zones += [PSCustomObject]@{
				ZoneIndex  = $zoneIndex
				X          = $zoneX
				Y          = $zoneY
				Width      = $zoneWidth
				Height     = $zoneHeight
				MonitorX   = $MonitorX
				MonitorY   = $MonitorY
				LayoutName = $LayoutName
			}
		}

		return $zones
	}
	catch {
		Write-Error "Failed to calculate zone coordinates: $_"
		return $null
	}
}
