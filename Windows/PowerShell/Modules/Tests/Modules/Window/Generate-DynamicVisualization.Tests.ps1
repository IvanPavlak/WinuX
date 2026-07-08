#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Generate-DynamicVisualization" {
	Context "Simple Layouts" {
		It "Should generate visualization for a 1x2 grid (two columns)" {
			$layoutInfo = @{
				'cell-child-map'     = @(, @(0, 1))
				'columns-percentage' = @(5000, 5000)
			}

			$result = Generate-DynamicVisualization -LayoutInfo $layoutInfo -ZoneContent @{} -ZoneNames @{ 0 = "Left"; 1 = "Right" }

			$result | Should -Not -BeNullOrEmpty
			# Should have box-drawing top border with junction
			$result | Should -Match "┌.*┬.*┐"
			# Should have bottom border with junction
			$result | Should -Match "└.*┴.*┘"
			# Should contain zone names
			$result | Should -Match "Left"
			$result | Should -Match "Right"
		}

		It "Should generate visualization for a 2x1 grid (two rows)" {
			$layoutInfo = @{
				'cell-child-map'     = @(@(0), @(1))
				'columns-percentage' = @(10000)
			}

			$result = Generate-DynamicVisualization -LayoutInfo $layoutInfo -ZoneContent @{} -ZoneNames @{ 0 = "Top"; 1 = "Bottom" }

			$result | Should -Not -BeNullOrEmpty
			# Should have horizontal separator
			$result | Should -Match "├.*┤"
			$result | Should -Match "Top"
			$result | Should -Match "Bottom"
		}

		It "Should generate visualization for a 2x2 grid" {
			$layoutInfo = @{
				'cell-child-map'     = @(@(0, 1), @(2, 3))
				'columns-percentage' = @(5000, 5000)
			}

			$result = Generate-DynamicVisualization -LayoutInfo $layoutInfo -ZoneContent @{} -ZoneNames @{ 0 = "TL"; 1 = "TR"; 2 = "BL"; 3 = "BR" }

			$result | Should -Match "TL"
			$result | Should -Match "TR"
			$result | Should -Match "BL"
			$result | Should -Match "BR"
			# Should have cross junction for 2x2 inner intersection
			$result | Should -Match "┼"
		}
	}

	Context "Zone Content Rendering" {
		It "Should display zone content instead of zone name when provided" {
			$layoutInfo = @{
				'cell-child-map'     = @(, @(0, 1))
				'columns-percentage' = @(5000, 5000)
			}

			$zoneContent = @{
				0 = @("Firefox")
				1 = @("VSCode")
			}

			$result = Generate-DynamicVisualization -LayoutInfo $layoutInfo -ZoneContent $zoneContent -ZoneNames @{ 0 = "Left"; 1 = "Right" }

			$result | Should -Match "Firefox"
			$result | Should -Match "VSCode"
			# Zone names should NOT appear when content is provided
			$result | Should -Not -Match "Left"
			$result | Should -Not -Match "Right"
		}

		It "Should show zone names for empty zones" {
			$layoutInfo = @{
				'cell-child-map'     = @(, @(0, 1))
				'columns-percentage' = @(5000, 5000)
			}

			$zoneContent = @{
				0 = @("Firefox")
			}

			$result = Generate-DynamicVisualization -LayoutInfo $layoutInfo -ZoneContent $zoneContent -ZoneNames @{ 0 = "Left"; 1 = "Right" }

			$result | Should -Match "Firefox"
			$result | Should -Match "Right"
		}

		It "Should fall back to 'Zone N' when zone name is not provided" {
			$layoutInfo = @{
				'cell-child-map'     = @(, @(0, 1))
				'columns-percentage' = @(5000, 5000)
			}

			$result = Generate-DynamicVisualization -LayoutInfo $layoutInfo -ZoneContent @{} -ZoneNames @{}

			$result | Should -Match "Zone 0"
			$result | Should -Match "Zone 1"
		}
	}

	Context "Spanning Zones" {
		It "Should handle vertically spanning zones without horizontal separator" {
			# Zone 0 spans both rows
			$layoutInfo = @{
				'cell-child-map'     = @(@(0, 1), @(0, 2))
				'columns-percentage' = @(5000, 5000)
			}

			$result = Generate-DynamicVisualization -LayoutInfo $layoutInfo -ZoneContent @{} -ZoneNames @{ 0 = "Full-Left"; 1 = "Top-Right"; 2 = "Bottom-Right" }

			$result | Should -Match "Full-Left"
			$result | Should -Match "Top-Right"
			$result | Should -Match "Bottom-Right"
		}

		It "Should handle horizontally spanning zones" {
			# Zone 0 spans both columns in row 0
			$layoutInfo = @{
				'cell-child-map'     = @(@(0, 0), @(1, 2))
				'columns-percentage' = @(5000, 5000)
			}

			$result = Generate-DynamicVisualization -LayoutInfo $layoutInfo -ZoneContent @{} -ZoneNames @{ 0 = "Top-Full"; 1 = "Bot-Left"; 2 = "Bot-Right" }

			$result | Should -Match "Top-Full"
			$result | Should -Match "Bot-Left"
			$result | Should -Match "Bot-Right"
		}
	}

	Context "Edge Cases" {
		It "Should handle a single-cell fullscreen layout" {
			$layoutInfo = @{
				'cell-child-map'     = @(, @(0))
				'columns-percentage' = @(10000)
			}

			$result = Generate-DynamicVisualization -LayoutInfo $layoutInfo -ZoneContent @{} -ZoneNames @{ 0 = "Full" }

			$result | Should -Match "Full"
			# No junction characters for single cell
			$result | Should -Not -Match "┬"
			$result | Should -Not -Match "┴"
		}

		It "Should respect TotalWidth parameter" {
			$layoutInfo = @{
				'cell-child-map'     = @(, @(0))
				'columns-percentage' = @(10000)
			}

			$result30 = Generate-DynamicVisualization -LayoutInfo $layoutInfo -ZoneContent @{} -TotalWidth 30
			$result80 = Generate-DynamicVisualization -LayoutInfo $layoutInfo -ZoneContent @{} -TotalWidth 80

			$lines30 = $result30 -split "`n"
			$lines80 = $result80 -split "`n"
			# Wider TotalWidth should produce wider lines
			$lines80[0].Length | Should -BeGreaterThan $lines30[0].Length
		}
	}
}
