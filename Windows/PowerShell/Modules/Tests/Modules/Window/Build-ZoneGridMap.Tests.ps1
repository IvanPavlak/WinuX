#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Build-ZoneGridMap" {
	Context "Simple Grid Layouts" {
		It "Should correctly identify zone boundaries for a 2x2 grid with 4 zones" {
			$cellChildMap = @(
				@(0, 1),
				@(2, 3)
			)

			$result = Build-ZoneGridMap -CellChildMap $cellChildMap

			$result.NumRows | Should -Be 2
			$result.NumCols | Should -Be 2
			$result.ZoneMap.Count | Should -Be 4

			# Zone 0 should be top-left only
			$result.ZoneMap[0].MinRow | Should -Be 0
			$result.ZoneMap[0].MaxRow | Should -Be 0
			$result.ZoneMap[0].MinCol | Should -Be 0
			$result.ZoneMap[0].MaxCol | Should -Be 0
		}

		It "Should correctly map a standard 3x3 nine-zone grid" {
			$cellChildMap = @(
				@(0, 1, 2),
				@(3, 4, 5),
				@(6, 7, 8)
			)

			$result = Build-ZoneGridMap -CellChildMap $cellChildMap

			$result.NumRows | Should -Be 3
			$result.NumCols | Should -Be 3
			$result.ZoneMap.Count | Should -Be 9

			# Each zone should be exactly one cell
			foreach ($zoneIndex in 0..8) {
				$result.ZoneMap[$zoneIndex].Cells.Count | Should -Be 1
			}
		}
	}

	Context "Grid with Spanning Zones" {
		It "Should detect horizontally spanning zones correctly" {
			# Zone 0 spans two columns in the first row
			$cellChildMap = @(
				@(0, 0),
				@(1, 2)
			)

			$result = Build-ZoneGridMap -CellChildMap $cellChildMap

			$result.ZoneMap.Count | Should -Be 3
			$result.ZoneMap[0].MinCol | Should -Be 0
			$result.ZoneMap[0].MaxCol | Should -Be 1
			$result.ZoneMap[0].Cells.Count | Should -Be 2
		}

		It "Should detect vertically spanning zones correctly" {
			# Zone 0 spans two rows in the first column
			$cellChildMap = @(
				@(0, 1),
				@(0, 2)
			)

			$result = Build-ZoneGridMap -CellChildMap $cellChildMap

			$result.ZoneMap.Count | Should -Be 3
			$result.ZoneMap[0].MinRow | Should -Be 0
			$result.ZoneMap[0].MaxRow | Should -Be 1
			$result.ZoneMap[0].Cells.Count | Should -Be 2
		}

		It "Should detect L-shaped zones correctly" {
			# Zone 0 forms an L-shape
			$cellChildMap = @(
				@(0, 0, 1),
				@(0, 2, 3),
				@(0, 4, 5)
			)

			$result = Build-ZoneGridMap -CellChildMap $cellChildMap

			$result.ZoneMap[0].MinRow | Should -Be 0
			$result.ZoneMap[0].MaxRow | Should -Be 2
			$result.ZoneMap[0].MinCol | Should -Be 0
			$result.ZoneMap[0].MaxCol | Should -Be 1
			$result.ZoneMap[0].Cells.Count | Should -Be 4
		}

		It "Should handle 2x3 grid with mixed spans (like layout Seven)" {
			# Simulates: Left | Middle | Top-Right
			#            Left | Middle | Bottom-Right
			$cellChildMap = @(
				@(0, 1, 2),
				@(0, 1, 3)
			)

			$result = Build-ZoneGridMap -CellChildMap $cellChildMap

			$result.ZoneMap.Count | Should -Be 4
			# Zone 0 (Left) spans both rows, column 0
			$result.ZoneMap[0].Cells.Count | Should -Be 2
			$result.ZoneMap[0].MinRow | Should -Be 0
			$result.ZoneMap[0].MaxRow | Should -Be 1
			# Zone 1 (Middle) spans both rows, column 1
			$result.ZoneMap[1].Cells.Count | Should -Be 2
		}
	}

	Context "Edge Cases" {
		It "Should handle a single-cell grid" {
			$cellChildMap = @(@(0))

			$result = Build-ZoneGridMap -CellChildMap $cellChildMap

			$result.NumRows | Should -Be 1
			$result.NumCols | Should -Be 1
			$result.ZoneMap.Count | Should -Be 1
		}

		It "Should handle a full-span single zone covering entire grid" {
			$cellChildMap = @(
				@(0, 0),
				@(0, 0)
			)

			$result = Build-ZoneGridMap -CellChildMap $cellChildMap

			$result.ZoneMap.Count | Should -Be 1
			$result.ZoneMap[0].MinRow | Should -Be 0
			$result.ZoneMap[0].MaxRow | Should -Be 1
			$result.ZoneMap[0].MinCol | Should -Be 0
			$result.ZoneMap[0].MaxCol | Should -Be 1
			$result.ZoneMap[0].Cells.Count | Should -Be 4
		}

		It "Should handle a wide 1xN grid" {
			# Use comma operator to force single-element outer array
			$cellChildMap = , @(0, 1, 2, 3, 4)

			$result = Build-ZoneGridMap -CellChildMap $cellChildMap

			$result.NumRows | Should -Be 1
			$result.NumCols | Should -Be 5
			$result.ZoneMap.Count | Should -Be 5
		}

		It "Should handle a tall Nx1 grid" {
			$cellChildMap = @(
				@(0),
				@(1),
				@(2),
				@(3)
			)

			$result = Build-ZoneGridMap -CellChildMap $cellChildMap

			$result.NumRows | Should -Be 4
			$result.NumCols | Should -Be 1
			$result.ZoneMap.Count | Should -Be 4
		}
	}
}
