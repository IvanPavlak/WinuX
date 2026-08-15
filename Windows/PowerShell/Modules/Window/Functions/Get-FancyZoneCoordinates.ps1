function Get-FancyZoneCoordinates {
	<#
	.SYNOPSIS
		Calculates zone coordinates from FancyZones custom layouts.

	.DESCRIPTION
		Parses the FancyZones custom-layouts.json file and calculates the actual pixel
		coordinates for each zone, replicating the zone math PowerToys FancyZones itself
		uses so the computed rectangles match what FancyZones snaps windows to.

		Both layout types are supported:

		- grid: rows/columns percentages plus a cell-child-map (possibly with spanning
		  zones). Row and column edges are computed with cumulative prefix sums so the
		  cells always add up to exactly the monitor work area, regardless of how the
		  percentages divide (e.g. 3333/3333/3334). Spacing follows the FancyZones model:
		  the FULL spacing value is inset on edges that touch the work-area border, and
		  Floor(spacing / 2) is inset per zone on interior edges (so two adjacent zones
		  leave 2 * Floor(spacing / 2) pixels between them). Any spacing value works -
		  there is no requirement to keep spacing at any particular number. A zone that
		  spans multiple cells absorbs the spacing between the cells it covers, because
		  only the zone's own outer edges are inset.

		- canvas: freely drawn zones with explicit X/Y/width/height rectangles in the
		  layout's ref-width/ref-height coordinate space. Each rectangle is scaled to the
		  monitor work area (MonitorWidth / ref-width, MonitorHeight / ref-height).
		  Canvas layouts ignore spacing entirely; zone index is the zone's position in
		  the layout's zones array.

		MonitorWidth/MonitorHeight must be the monitor WORK AREA (excluding the taskbar),
		matching what FancyZones itself zones against.

	.PARAMETER LayoutName
		The name of the FancyZones layout as defined in custom-layouts.json.

	.PARAMETER MonitorX
		The X position of the monitor work area (default: 0).

	.PARAMETER MonitorY
		The Y position of the monitor work area (default: 0).

	.PARAMETER MonitorWidth
		The width of the monitor work area in pixels (default: 3440).

	.PARAMETER MonitorHeight
		The height of the monitor work area in pixels (default: 1440).

	.PARAMETER CustomLayoutsPath
		Optional path to custom-layouts.json file. If not specified, uses the repository's
		FancyZones configuration (the symlink target of the PowerToys custom layouts file).

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
		if ($global:MachineSpecificPaths.SymbolicLinks.PowerToys.CustomLayouts.Target) {
			$CustomLayoutsPath = $global:MachineSpecificPaths.SymbolicLinks.PowerToys.CustomLayouts.Target
		}
		else {
			# Only reached when the path configuration is not loaded (tests, standalone use).
			$CustomLayoutsPath = Get-FancyZonesLayoutsPath
		}
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

		switch ($layout.type) {
			"grid" {
				return Get-GridZoneCoordinates -Layout $layout -LayoutName $LayoutName `
					-MonitorX $MonitorX -MonitorY $MonitorY `
					-MonitorWidth $MonitorWidth -MonitorHeight $MonitorHeight
			}
			"canvas" {
				return Get-CanvasZoneCoordinates -Layout $layout -LayoutName $LayoutName `
					-MonitorX $MonitorX -MonitorY $MonitorY `
					-MonitorWidth $MonitorWidth -MonitorHeight $MonitorHeight
			}
			default {
				Write-Warning "Only grid and canvas layouts are supported. Layout '$LayoutName' is type '$($layout.type)'"
				return $null
			}
		}
	}
	catch {
		Write-Error "Failed to calculate zone coordinates: $_"
		return $null
	}
}

function Get-GridZoneCoordinates {
	<#
	.SYNOPSIS
		Computes pixel rectangles for a FancyZones grid layout (internal helper).

	.DESCRIPTION
		Replicates PowerToys FancyZones' CalculateGridZones: cumulative prefix-sum
		row/column edges (floor division, cells sum exactly to the work area), full
		spacing inset on work-area edges, Floor(spacing / 2) inset per interior edge.
		Called by Get-FancyZoneCoordinates; not intended for direct use.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		$Layout,

		[Parameter(Mandatory = $true)]
		[string]$LayoutName,

		[Parameter(Mandatory = $true)]
		[int]$MonitorX,

		[Parameter(Mandatory = $true)]
		[int]$MonitorY,

		[Parameter(Mandatory = $true)]
		[int]$MonitorWidth,

		[Parameter(Mandatory = $true)]
		[int]$MonitorHeight
	)

	$rows = [int]$Layout.info.rows
	$columns = [int]$Layout.info.columns
	$rowPercentages = @($Layout.info.'rows-percentage')
	$columnPercentages = @($Layout.info.'columns-percentage')
	$cellChildMap = @($Layout.info.'cell-child-map')
	$spacing = if ($Layout.info.'show-spacing') { [int]$Layout.info.spacing } else { 0 }

	# Arbitrary user edits are expected here - fail loudly on malformed definitions
	# instead of producing rectangles that silently disagree with FancyZones.
	if ($rows -lt 1 -or $columns -lt 1) {
		Write-Error "Layout '$LayoutName': rows ($rows) and columns ($columns) must both be at least 1"
		return $null
	}
	if ($rowPercentages.Count -ne $rows) {
		Write-Error "Layout '$LayoutName': rows-percentage has $($rowPercentages.Count) entries but rows is $rows"
		return $null
	}
	if ($columnPercentages.Count -ne $columns) {
		Write-Error "Layout '$LayoutName': columns-percentage has $($columnPercentages.Count) entries but columns is $columns"
		return $null
	}
	if ($cellChildMap.Count -ne $rows) {
		Write-Error "Layout '$LayoutName': cell-child-map has $($cellChildMap.Count) rows but rows is $rows"
		return $null
	}
	for ($row = 0; $row -lt $rows; $row++) {
		if (@($cellChildMap[$row]).Count -ne $columns) {
			Write-Error "Layout '$LayoutName': cell-child-map row $row has $(@($cellChildMap[$row]).Count) entries but columns is $columns"
			return $null
		}
	}
	if ($spacing -lt 0) {
		Write-Error "Layout '$LayoutName': spacing ($spacing) must not be negative"
		return $null
	}

	# Row and column edges as cumulative prefix sums with floor division - the exact
	# expression FancyZones uses. Written this way (instead of summing per-cell sizes)
	# so the last edge always lands on the work-area boundary and no pixels are lost
	# to rounding, whatever the percentages are. [Math]::Floor, never [int] casts:
	# [int] rounds half to even, which diverges from C++ integer division.
	$rowStart = New-Object 'int[]' $rows
	$rowEnd = New-Object 'int[]' $rows
	$totalPercent = 0
	for ($row = 0; $row -lt $rows; $row++) {
		$rowStart[$row] = [Math]::Floor($totalPercent * $MonitorHeight / 10000)
		$totalPercent += [int]$rowPercentages[$row]
		$rowEnd[$row] = [Math]::Floor($totalPercent * $MonitorHeight / 10000)
	}

	$colStart = New-Object 'int[]' $columns
	$colEnd = New-Object 'int[]' $columns
	$totalPercent = 0
	for ($col = 0; $col -lt $columns; $col++) {
		$colStart[$col] = [Math]::Floor($totalPercent * $MonitorWidth / 10000)
		$totalPercent += [int]$columnPercentages[$col]
		$colEnd[$col] = [Math]::Floor($totalPercent * $MonitorWidth / 10000)
	}

	# Build a map of zone index to cell ranges. JSON numbers arrive as Int64 -
	# cast to [int] so hashtable keys compare consistently.
	$zoneMap = @{}
	for ($row = 0; $row -lt $rows; $row++) {
		for ($col = 0; $col -lt $columns; $col++) {
			$zoneIndex = [int]$cellChildMap[$row][$col]

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

	# FancyZones spacing model: edges touching the work-area border are inset by the
	# FULL spacing; interior edges by Floor(spacing / 2) per zone. A spanning zone runs
	# from its first cell's start edge to its last cell's end edge, so the spacing
	# between the cells it covers is absorbed into the zone automatically.
	$halfSpacing = [int][Math]::Floor($spacing / 2)

	$zones = @()
	foreach ($zoneIndex in ($zoneMap.Keys | Sort-Object)) {
		$zone = $zoneMap[$zoneIndex]

		$left = $colStart[$zone.MinCol]
		$right = $colEnd[$zone.MaxCol]
		$top = $rowStart[$zone.MinRow]
		$bottom = $rowEnd[$zone.MaxRow]

		$top += if ($zone.MinRow -eq 0) { $spacing } else { $halfSpacing }
		$left += if ($zone.MinCol -eq 0) { $spacing } else { $halfSpacing }
		$bottom -= if ($zone.MaxRow -eq ($rows - 1)) { $spacing } else { $halfSpacing }
		$right -= if ($zone.MaxCol -eq ($columns - 1)) { $spacing } else { $halfSpacing }

		$zones += [PSCustomObject]@{
			ZoneIndex  = $zoneIndex
			X          = $MonitorX + $left
			Y          = $MonitorY + $top
			Width      = $right - $left
			Height     = $bottom - $top
			MonitorX   = $MonitorX
			MonitorY   = $MonitorY
			LayoutName = $LayoutName
		}
	}

	return $zones
}

function Get-CanvasZoneCoordinates {
	<#
	.SYNOPSIS
		Computes pixel rectangles for a FancyZones canvas layout (internal helper).

	.DESCRIPTION
		Replicates PowerToys FancyZones' canvas zone math: each zone rectangle, defined
		in the layout's ref-width/ref-height coordinate space, is scaled to the monitor
		work area. Canvas layouts ignore spacing; zone index is the position in the
		layout's zones array. Called by Get-FancyZoneCoordinates; not intended for
		direct use.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		$Layout,

		[Parameter(Mandatory = $true)]
		[string]$LayoutName,

		[Parameter(Mandatory = $true)]
		[int]$MonitorX,

		[Parameter(Mandatory = $true)]
		[int]$MonitorY,

		[Parameter(Mandatory = $true)]
		[int]$MonitorWidth,

		[Parameter(Mandatory = $true)]
		[int]$MonitorHeight
	)

	$refWidth = [int]$Layout.info.'ref-width'
	$refHeight = [int]$Layout.info.'ref-height'
	$canvasZones = @($Layout.info.zones)

	if ($refWidth -le 0 -or $refHeight -le 0) {
		Write-Error "Layout '$LayoutName': ref-width ($refWidth) and ref-height ($refHeight) must both be positive"
		return $null
	}
	if ($canvasZones.Count -eq 0) {
		Write-Error "Layout '$LayoutName': canvas layout defines no zones"
		return $null
	}

	$scaleX = $MonitorWidth / $refWidth
	$scaleY = $MonitorHeight / $refHeight

	$zones = @()
	for ($index = 0; $index -lt $canvasZones.Count; $index++) {
		$canvasZone = $canvasZones[$index]

		$zones += [PSCustomObject]@{
			ZoneIndex  = $index
			X          = $MonitorX + [int][Math]::Floor([int]$canvasZone.X * $scaleX)
			Y          = $MonitorY + [int][Math]::Floor([int]$canvasZone.Y * $scaleY)
			Width      = [int][Math]::Floor([int]$canvasZone.width * $scaleX)
			Height     = [int][Math]::Floor([int]$canvasZone.height * $scaleY)
			MonitorX   = $MonitorX
			MonitorY   = $MonitorY
			LayoutName = $LayoutName
		}
	}

	return $zones
}
