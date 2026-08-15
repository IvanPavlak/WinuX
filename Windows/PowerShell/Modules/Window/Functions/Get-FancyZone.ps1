function Get-FancyZone {
	<#
	.SYNOPSIS
		Gets FancyZone coordinates using human-readable zone names.

	.DESCRIPTION
		Provides a user-friendly interface to get zone coordinates by using descriptive
		zone names instead of numeric indices. Supports common zone names based on layout type.

	.PARAMETER LayoutName
		The name of the FancyZones layout (e.g., "Zero", "One", "Seven").

	.PARAMETER ZoneName
		Human-readable zone name. Available names are defined per layout in
		$Configuration.ZoneNameMappings (Configuration.psd1), which maps each name to a
		zone index in that layout's custom-layouts.json definition. Multiple names may
		map to the same index (e.g. "Left" and "Far-Left"). Run
		Visualize-Layouts -DisplayAvailableLayouts to see every layout with its zone
		names in position, and Test-FancyZonesConfiguration to verify the mappings
		agree with custom-layouts.json.

	.PARAMETER MonitorX
		The X position of the monitor (default: 0).

	.PARAMETER MonitorY
		The Y position of the monitor (default: 0).

	.PARAMETER MonitorWidth
		The width of the monitor in pixels (default: 3440).

	.PARAMETER MonitorHeight
		The height of the monitor in pixels (default: 1440).

	.PARAMETER CustomLayoutsPath
		Optional path to custom-layouts.json file.

	.EXAMPLE
		Get-FancyZone -LayoutName "Seven" -ZoneName "Left" -MonitorY -1440

	.EXAMPLE
		$zone = Get-FancyZone -LayoutName "One" -ZoneName "Right"
		Set-WindowPosition -WindowHandle $handle -X $zone.X -Y $zone.Y -Width $zone.Width -Height $zone.Height
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$LayoutName,

		[Parameter(Mandatory = $true)]
		[string]$ZoneName,

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

	if (-not $global:Configuration) {
		Write-Error "Global configuration not loaded. Re run Load-PathConfiguration!"
		return $null
	}
	$zoneNameMappings = $global:Configuration.ZoneNameMappings

	# Check if layout has zone name mappings
	if (-not $zoneNameMappings.ContainsKey($LayoutName)) {
		Write-Error "Layout '$LayoutName' does not have zone name mappings defined"
		Write-LogStep "Available layouts:" -NoLeadingNewline
		$zoneNameMappings.Keys | Sort-Object | ForEach-Object {
			Write-LogStep "  - $_" -NoLeadingNewline
		}
		return $null
	}

	# Get zone index from zone name
	$zoneIndex = $zoneNameMappings[$LayoutName][$ZoneName]

	if ($null -eq $zoneIndex) {
		Write-Error "Zone name '$ZoneName' not found for layout '$LayoutName'"
		Write-LogStep "Available zone names for layout '$LayoutName':" -NoLeadingNewline
		$zoneNameMappings[$LayoutName].Keys | Sort-Object | ForEach-Object {
			Write-LogStep "  - $_ (Zone $($zoneNameMappings[$LayoutName][$_]))" -NoLeadingNewline
		}
		return $null
	}

	# Get all zones for this layout
	$params = @{
		LayoutName    = $LayoutName
		MonitorX      = $MonitorX
		MonitorY      = $MonitorY
		MonitorWidth  = $MonitorWidth
		MonitorHeight = $MonitorHeight
	}
	if ($CustomLayoutsPath) {
		$params.CustomLayoutsPath = $CustomLayoutsPath
	}

	$zones = Get-FancyZoneCoordinates @params

	if (-not $zones) {
		return $null
	}

	# Find the requested zone
	$zone = $zones | Where-Object { $_.ZoneIndex -eq $zoneIndex } | Select-Object -First 1

	if (-not $zone) {
		$availableIndices = @($zones | ForEach-Object { $_.ZoneIndex }) -join ', '
		Write-Error "Zone name '$ZoneName' maps to index $zoneIndex, but layout '$LayoutName' defines $(@($zones).Count) zones (indices: $availableIndices) - check the ZoneNameMappings entry for '$LayoutName' in Configuration.psd1 against custom-layouts.json (run Test-FancyZonesConfiguration)"
		return $null
	}

	# Add the zone name to the result
	$zone | Add-Member -NotePropertyName "ZoneName" -NotePropertyValue $ZoneName -Force

	return $zone
}
