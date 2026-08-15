function Format-CanvasZoneListing {
	<#
	.SYNOPSIS
		Renders a FancyZones canvas layout as a textual per-zone listing.

	.DESCRIPTION
		Canvas layouts are free-form rectangles (possibly overlapping), so they cannot
		be drawn as a proportional ASCII grid the way grid layouts are. This renders
		one line per zone instead, with the zone's position and size expressed as
		percentages of the layout's ref-width/ref-height coordinate space, e.g.:

			Zone 0 [Left]: x=0.0% y=0.0% w=50.0% h=100.0%

		Zone names come from the optional ZoneNames map (zone index -> name); zone
		content (e.g. process names) from the optional ZoneContent map.

	.PARAMETER LayoutInfo
		The canvas layout's info object from custom-layouts.json (ref-width,
		ref-height, zones).

	.PARAMETER ZoneContent
		Optional hashtable mapping zone index to an array of content labels
		(e.g. process names) to display after the zone geometry.

	.PARAMETER ZoneNames
		Optional hashtable mapping zone index to a human-readable zone name.

	.EXAMPLE
		Format-CanvasZoneListing -LayoutInfo $layoutDef.info -ZoneContent @{} -ZoneNames @{ 0 = "Left" }

	.OUTPUTS
		String containing one line per zone.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		$LayoutInfo,

		[Parameter()]
		[hashtable]$ZoneContent = @{},

		[Parameter()]
		[hashtable]$ZoneNames = @{}
	)

	$refWidth = [int]$LayoutInfo.'ref-width'
	$refHeight = [int]$LayoutInfo.'ref-height'
	$canvasZones = @($LayoutInfo.zones)

	if ($refWidth -le 0 -or $refHeight -le 0 -or $canvasZones.Count -eq 0) {
		return "Canvas layout has no drawable zones (ref-width=$refWidth, ref-height=$refHeight, zones=$($canvasZones.Count))"
	}

	$lines = @()
	for ($index = 0; $index -lt $canvasZones.Count; $index++) {
		$zone = $canvasZones[$index]

		$xPercent = [Math]::Round(100 * [int]$zone.X / $refWidth, 1)
		$yPercent = [Math]::Round(100 * [int]$zone.Y / $refHeight, 1)
		$wPercent = [Math]::Round(100 * [int]$zone.width / $refWidth, 1)
		$hPercent = [Math]::Round(100 * [int]$zone.height / $refHeight, 1)

		$nameLabel = if ($ZoneNames.ContainsKey($index)) { " [$($ZoneNames[$index])]" } else { "" }
		$line = "Zone $index${nameLabel}: x=$xPercent% y=$yPercent% w=$wPercent% h=$hPercent%"

		if ($ZoneContent.ContainsKey($index) -and @($ZoneContent[$index]).Count -gt 0) {
			$contentLabels = @($ZoneContent[$index]) | ForEach-Object { ($_ -split "`n")[0] }
			$line += " => $($contentLabels -join ', ')"
		}

		$lines += $line
	}

	return $lines -join "`n"
}
