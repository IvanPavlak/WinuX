function Generate-DynamicVisualization {
	<#
	.SYNOPSIS
		Dynamically generates ASCII visualization for any grid-based layout.

	.DESCRIPTION
		Analyzes a FancyZones grid layout definition and generates an ASCII art
		visualization showing zone boundaries and content. Works with any grid-based
		layout configuration by dynamically calculating column widths, row heights,
		and rendering appropriate box-drawing characters based on zone boundaries.

	.PARAMETER LayoutInfo
		Layout info containing cell-child-map from the FancyZones layout definition.

	.PARAMETER ZoneContent
		Hashtable of zone index to content array (e.g., process names and window titles).

	.PARAMETER ZoneNames
		Hashtable mapping zone index to human-readable zone name (e.g., 0 -> "Top-Left").
		Used for displaying meaningful labels in empty zones.

	.PARAMETER TotalWidth
		Total width available for the visualization (default 54).

	.EXAMPLE
		$visual = Generate-DynamicVisualization -LayoutInfo $layoutDef.info -ZoneContent $zoneContent -ZoneNames $zoneIndexToName

	.EXAMPLE
		Generate-DynamicVisualization -LayoutInfo $layout.info -ZoneContent @{0 = @("Firefox", "YouTube")} -ZoneNames @{0 = "Top-Left"; 1 = "Top-Right"} -TotalWidth 80

	.OUTPUTS
		String containing the ASCII visualization with box-drawing characters.
	#>
	param (
		[object]$LayoutInfo,
		[hashtable]$ZoneContent,
		[hashtable]$ZoneNames = @{},
		[int]$TotalWidth = 54
	)

	$cellMap = $LayoutInfo.'cell-child-map'
	$gridInfo = Build-ZoneGridMap -CellChildMap $cellMap
	$numRows = $gridInfo.NumRows
	$numCols = $gridInfo.NumCols
	$zoneMap = $gridInfo.ZoneMap

	# Calculate column widths proportionally based on columns-percentage
	# Available width for content = TotalWidth - (numCols + 1) borders - (numCols * 2) padding
	$availableContentWidth = $TotalWidth - ($numCols + 1) - ($numCols * 2)

	# Get column percentages from layout info (values are out of 10000)
	$colPercentages = $LayoutInfo.'columns-percentage'

	$colWidths = @()
	if ($colPercentages -and $colPercentages.Count -eq $numCols) {
		# Calculate proportional widths based on percentages
		$totalPercentage = ($colPercentages | Measure-Object -Sum).Sum
		$allocatedWidth = 0

		for ($i = 0; $i -lt $numCols; $i++) {
			if ($i -eq $numCols - 1) {
				# Last column gets remaining width to avoid rounding errors
				$colWidth = $availableContentWidth - $allocatedWidth
			}
			else {
				$colWidth = [Math]::Floor($availableContentWidth * $colPercentages[$i] / $totalPercentage)
				$allocatedWidth += $colWidth
			}
			# Ensure minimum width per column
			if ($colWidth -lt 8) { $colWidth = 8 }
			$colWidths += $colWidth
		}
	}
 else {
		# Fallback to equal widths if no percentages available
		$baseColWidth = [Math]::Floor($availableContentWidth / $numCols)
		if ($baseColWidth -lt 8) { $baseColWidth = 8 }

		for ($i = 0; $i -lt $numCols; $i++) {
			if ($i -eq $numCols - 1) {
				$colWidths += $availableContentWidth - ($baseColWidth * ($numCols - 1))
			}
			else {
				$colWidths += $baseColWidth
			}
		}
	}

	# Use minimum column width for content formatting (simplifies logic)
	$colWidth = ($colWidths | Measure-Object -Minimum).Minimum

	# Build row heights - determine how many lines each row needs
	$rowHeights = @()
	for ($row = 0; $row -lt $numRows; $row++) {
		$maxLinesInRow = 2  # Minimum height

		for ($col = 0; $col -lt $numCols; $col++) {
			# Convert to Int32 to match hashtable key type (JSON parsing returns Int64)
			$zoneIndex = [int]$cellMap[$row][$col]
			$zone = $zoneMap[$zoneIndex]

			# Only calculate content for zones that start in this row
			if ($zone.MinRow -eq $row) {
				$content = if ($ZoneContent.ContainsKey($zoneIndex) -and $ZoneContent[$zoneIndex].Count -gt 0) {
					Format-ZoneContent -Content $ZoneContent[$zoneIndex] -Width $colWidth
				}
				else {
					# Use zone name if available, otherwise "Zone N"
					$zoneName = if ($ZoneNames.ContainsKey($zoneIndex)) { $ZoneNames[$zoneIndex] } else { "Zone $zoneIndex" }
					# Ensure zone name is never empty
					if ([string]::IsNullOrWhiteSpace($zoneName)) {
						$zoneName = "Zone $zoneIndex"
					}
					Format-ZoneContent -Content @($zoneName) -Width $colWidth
				}

				# Distribute content across rows this zone spans
				$rowSpan = $zone.MaxRow - $zone.MinRow + 1
				$linesPerRow = [Math]::Ceiling($content.Count / $rowSpan)
				$maxLinesInRow = [Math]::Max($maxLinesInRow, $linesPerRow)
			}
		}

		$rowHeights += $maxLinesInRow
	}

	# Generate ASCII art
	$visual = ""

	# Top border
	$visual += "┌"
	for ($col = 0; $col -lt $numCols; $col++) {
		$visual += ("─" * ($colWidths[$col] + 2))
		if ($col -lt $numCols - 1) {
			$visual += "┬"
		}
	}
	$visual += "┐`n"

	# Content rows
	for ($row = 0; $row -lt $numRows; $row++) {
		# Determine which zones start in this row and cache their content
		$rowZoneContent = @{}
		for ($col = 0; $col -lt $numCols; $col++) {
			# Convert to Int32 to match hashtable key type (JSON parsing returns Int64)
			$zoneIndex = [int]$cellMap[$row][$col]
			if (-not $rowZoneContent.ContainsKey($zoneIndex)) {
				$zone = $zoneMap[$zoneIndex]
				if ($zone.MinRow -eq $row) {
					# Check if this zone has content (use ContainsKey to detect actual entries)
					$content = if ($ZoneContent.ContainsKey($zoneIndex) -and $ZoneContent[$zoneIndex].Count -gt 0) {
						Format-ZoneContent -Content $ZoneContent[$zoneIndex] -Width $colWidth
					}
					else {
						# Use zone name if available, otherwise "Zone N"
						$zoneName = if ($ZoneNames.ContainsKey($zoneIndex)) { $ZoneNames[$zoneIndex] } else { "Zone $zoneIndex" }
						# Ensure zone name is never empty
						if ([string]::IsNullOrWhiteSpace($zoneName)) {
							$zoneName = "Zone $zoneIndex"
						}
						Format-ZoneContent -Content @($zoneName) -Width $colWidth
					}
					$rowZoneContent[$zoneIndex] = $content
				}
			}
		}

		# Render lines for this row
		for ($line = 0; $line -lt $rowHeights[$row]; $line++) {
			$visual += "│"

			for ($col = 0; $col -lt $numCols; $col++) {
				# Convert to Int32 to match hashtable key type (JSON parsing returns Int64)
				$zoneIndex = [int]$cellMap[$row][$col]
				$zone = $zoneMap[$zoneIndex]

				# Use the specific column width for this column
				$currentColWidth = $colWidths[$col]

				# Get content for this zone
				if ($rowZoneContent.ContainsKey($zoneIndex)) {
					$content = $rowZoneContent[$zoneIndex]
					if ($line -lt $content.Count) {
						$contentText = [string]$content[$line]
						# Ensure we never pass empty string to Center-Text
						if ([string]::IsNullOrWhiteSpace($contentText)) {
							$text = " " * $currentColWidth
						}
						else {
							$text = Center-Text -Text $contentText -Width $currentColWidth
						}
					}
					else {
						$text = " " * $currentColWidth
					}
				}
				else {
					$text = " " * $currentColWidth
				}

				$visual += " $text │"
			}

			$visual += "`n"
		}

		# Row separator or bottom border
		if ($row -lt $numRows - 1) {
			# Determine separator type based on zone boundaries
			# Check left edge
			$leftZone = [int]$cellMap[$row][0]
			$leftBelowZone = [int]$cellMap[$row + 1][0]
			if ($leftZone -eq $leftBelowZone) {
				$visual += "│"
			}
			else {
				$visual += "├"
			}

			for ($col = 0; $col -lt $numCols - 1; $col++) {
				# Convert to Int32 to match hashtable key type (JSON parsing returns Int64)
				$currentZone = [int]$cellMap[$row][$col]
				$belowZone = [int]$cellMap[$row + 1][$col]
				$rightZone = [int]$cellMap[$row][$col + 1]
				$rightBelowZone = [int]$cellMap[$row + 1][$col + 1]

				# Use the specific column width for this column
				$currentColWidth = $colWidths[$col]

				# Determine horizontal line character
				if ($currentZone -eq $belowZone) {
					$visual += (" " * ($currentColWidth + 2))
				}
				else {
					$visual += ("─" * ($currentColWidth + 2))
				}

				# Determine intersection character
				$hasTop = ($currentZone -ne $rightZone)
				$hasBottom = ($belowZone -ne $rightBelowZone)
				$hasLeft = ($currentZone -ne $belowZone)
				$hasRight = ($rightZone -ne $rightBelowZone)

				if ($hasTop -and $hasBottom -and $hasLeft -and $hasRight) {
					$visual += "┼"
				}
				elseif ($hasTop -and $hasBottom -and $hasLeft) {
					$visual += "┤"
				}
				elseif ($hasTop -and $hasBottom -and $hasRight) {
					$visual += "├"
				}
				elseif ($hasTop -and $hasLeft -and $hasRight) {
					$visual += "┴"
				}
				elseif ($hasBottom -and $hasLeft -and $hasRight) {
					$visual += "┬"
				}
				elseif ($hasTop -and $hasBottom) {
					$visual += "│"
				}
				elseif ($hasLeft -and $hasRight) {
					$visual += "─"
				}
				elseif ($hasTop -and $hasLeft) {
					$visual += "┘"
				}
				elseif ($hasTop -and $hasRight) {
					$visual += "└"
				}
				elseif ($hasBottom -and $hasLeft) {
					$visual += "┐"
				}
				elseif ($hasBottom -and $hasRight) {
					$visual += "┌"
				}
				else {
					$visual += " "
				}
			}

			# Last column
			$lastCol = $numCols - 1
			$currentZone = [int]$cellMap[$row][$lastCol]
			$belowZone = [int]$cellMap[$row + 1][$lastCol]

			# Use the specific width for the last column (which may have extra width)
			$lastColWidth = $colWidths[$lastCol]

			if ($currentZone -eq $belowZone) {
				$visual += (" " * ($lastColWidth + 2))
			}
			else {
				$visual += ("─" * ($lastColWidth + 2))
			}

			# Check right edge
			if ($currentZone -eq $belowZone) {
				$visual += "│`n"
			}
			else {
				$visual += "┤`n"
			}
		}
	}

	# Bottom border
	$visual += "└"
	for ($col = 0; $col -lt $numCols; $col++) {
		$visual += ("─" * ($colWidths[$col] + 2))
		if ($col -lt $numCols - 1) {
			$visual += "┴"
		}
	}
	$visual += "┘"

	return $visual
}
