function Build-ZoneGridMap {
	<#
	.SYNOPSIS
		Builds a map of zones to their grid positions from cell-child-map.

	.DESCRIPTION
		Analyzes the cell-child-map from a FancyZones layout definition to determine
		which grid cells each zone occupies and calculates their boundaries (min/max rows/cols).
		Used internally by the dynamic visualization system.

	.PARAMETER CellChildMap
		The cell-child-map array from the layout definition.

	.EXAMPLE
		$gridInfo = Build-ZoneGridMap -CellChildMap $layoutDef.info.'cell-child-map'

	.OUTPUTS
		Hashtable containing:
		  - ZoneMap: Hashtable mapping zone indices to their cell positions and spans
		  - NumRows: Number of rows in the grid
		  - NumCols: Number of columns in the grid
	#>
	param (
		[array]$CellChildMap
	)

	$zoneMap = @{}
	$numRows = $CellChildMap.Count
	$numCols = $CellChildMap[0].Count

	# Build map of which cells each zone occupies
	for ($row = 0; $row -lt $numRows; $row++) {
		for ($col = 0; $col -lt $numCols; $col++) {
			# Convert to Int32 to match hashtable key type (JSON parsing returns Int64)
			$zoneIndex = [int]$CellChildMap[$row][$col]

			if (-not $zoneMap.ContainsKey($zoneIndex)) {
				$zoneMap[$zoneIndex] = @{
					MinRow = $row
					MaxRow = $row
					MinCol = $col
					MaxCol = $col
					Cells  = @()
				}
			}

			$zoneMap[$zoneIndex].Cells += @{Row = $row; Col = $col }
			$zoneMap[$zoneIndex].MinRow = [Math]::Min($zoneMap[$zoneIndex].MinRow, $row)
			$zoneMap[$zoneIndex].MaxRow = [Math]::Max($zoneMap[$zoneIndex].MaxRow, $row)
			$zoneMap[$zoneIndex].MinCol = [Math]::Min($zoneMap[$zoneIndex].MinCol, $col)
			$zoneMap[$zoneIndex].MaxCol = [Math]::Max($zoneMap[$zoneIndex].MaxCol, $col)
		}
	}

	return @{
		ZoneMap = $zoneMap
		NumRows = $numRows
		NumCols = $numCols
	}
}
