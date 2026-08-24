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
		The width of the monitor in pixels. Required - a non-positive value is an error rather
		than a cue to assume a display size.

	.PARAMETER MonitorHeight
		The height of the monitor in pixels. Required - a non-positive value is an error rather
		than a cue to assume a display size.

	.PARAMETER CustomLayoutsPath
		Optional path to custom-layouts.json file.

	.OUTPUTS
		The zone object from Get-FancyZoneCoordinates (X, Y, Width, Height, ZoneIndex, ...)
		with two members added: ZoneName (the requested human-readable name) and
		TotalZoneCount (how many zones the resolved layout defines - 1 marks a single-zone
		layout, which the snap pipeline places directly instead of snapping).

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
		[int]$MonitorWidth = 0,

		[Parameter()]
		[int]$MonitorHeight = 0,

		[Parameter()]
		[string]$CustomLayoutsPath
	)

	if (-not $global:Configuration) {
		Write-Error "Global configuration not loaded. Re run Load-PathConfiguration!"
		return $null
	}

	# These used to default to a 3440x1440 ultrawide. On a mixed-resolution setup that silently
	# computed zones for a display that may not be attached, so an omitted or zero dimension is
	# now an error: callers resolve real monitor geometry (Get-MonitorSpecs) or skip the entry.
	if ($MonitorWidth -le 0 -or $MonitorHeight -le 0) {
		Write-Error "Monitor geometry is required: MonitorWidth and MonitorHeight must both be greater than 0 (got ${MonitorWidth}x${MonitorHeight}). Resolve the monitor with Get-MonitorSpecs and pass its work area."
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

	# How many zones the resolved layout defines, straight from custom-layouts.json. A count
	# of 1 tells the snap pipeline the layout is single-zone (e.g. "Zero"), where FancyZones'
	# relative Win+Arrow has no neighbouring zone to disambiguate it and Snap-AllWindows must
	# place the window directly instead. Counting ZoneNameMappings keys would be wrong - two
	# names ("Full", "Fullscreen") map to the same index.
	$zone | Add-Member -NotePropertyName "TotalZoneCount" -NotePropertyValue (@($zones).Count) -Force

	return $zone
}
