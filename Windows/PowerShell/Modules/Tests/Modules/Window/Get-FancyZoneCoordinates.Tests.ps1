#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Get-FancyZoneCoordinates" {
	BeforeAll {
		# Create test layouts JSON with several layout configurations
		$script:TestLayoutsPath = Join-Path $TestDrive "test-custom-layouts.json"
		$testLayouts = @{
			'custom-layouts' = @(
				@{
					name = "EvenSplit"
					type = "grid"
					info = @{
						rows                 = 1
						columns              = 2
						'rows-percentage'    = @(10000)
						'columns-percentage' = @(5000, 5000)
						'cell-child-map'     = @(, @(0, 1))
						'show-spacing'       = $false
						spacing              = 0
					}
				}
				@{
					name = "FourQuadrants"
					type = "grid"
					info = @{
						rows                 = 2
						columns              = 2
						'rows-percentage'    = @(5000, 5000)
						'columns-percentage' = @(5000, 5000)
						'cell-child-map'     = @(@(0, 1), @(2, 3))
						'show-spacing'       = $false
						spacing              = 0
					}
				}
				@{
					name = "SpanningLayout"
					type = "grid"
					info = @{
						rows                 = 2
						columns              = 3
						'rows-percentage'    = @(5000, 5000)
						'columns-percentage' = @(3333, 3334, 3333)
						'cell-child-map'     = @(@(0, 1, 1), @(0, 2, 3))
						'show-spacing'       = $false
						spacing              = 0
					}
				}
				@{
					name = "WithSpacing"
					type = "grid"
					info = @{
						rows                 = 1
						columns              = 2
						'rows-percentage'    = @(10000)
						'columns-percentage' = @(5000, 5000)
						'cell-child-map'     = @(, @(0, 1))
						'show-spacing'       = $true
						spacing              = 20
					}
				}
				@{
					name = "UnevenSplit"
					type = "grid"
					info = @{
						rows                 = 1
						columns              = 2
						'rows-percentage'    = @(10000)
						'columns-percentage' = @(6667, 3333)
						'cell-child-map'     = @(, @(0, 1))
						'show-spacing'       = $false
						spacing              = 0
					}
				}
				@{
					name = "CanvasLayout"
					type = "canvas"
					info = @{}
				}
			)
		}
		$testLayouts | ConvertTo-Json -Depth 10 | Set-Content $script:TestLayoutsPath
	}

	Context "Coordinate Calculation" {
		It "Should calculate correct coordinates for a 50/50 horizontal split" {
			$zones = Get-FancyZoneCoordinates -LayoutName "EvenSplit" -MonitorX 0 -MonitorY 0 -MonitorWidth 1000 -MonitorHeight 500 -CustomLayoutsPath $script:TestLayoutsPath

			$zones | Should -Not -BeNullOrEmpty
			$zones.Count | Should -Be 2

			# Zone 0 (Left)
			$left = $zones | Where-Object { $_.ZoneIndex -eq 0 }
			$left.X | Should -Be 0
			$left.Y | Should -Be 0
			$left.Width | Should -Be 500
			$left.Height | Should -Be 500

			# Zone 1 (Right)
			$right = $zones | Where-Object { $_.ZoneIndex -eq 1 }
			$right.X | Should -Be 500
			$right.Y | Should -Be 0
			$right.Width | Should -Be 500
			$right.Height | Should -Be 500
		}

		It "Should calculate correct coordinates for a 2x2 grid" {
			$zones = Get-FancyZoneCoordinates -LayoutName "FourQuadrants" -MonitorX 0 -MonitorY 0 -MonitorWidth 1000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			$zones.Count | Should -Be 4

			$tl = $zones | Where-Object { $_.ZoneIndex -eq 0 }
			$tl.X | Should -Be 0
			$tl.Y | Should -Be 0
			$tl.Width | Should -Be 500
			$tl.Height | Should -Be 500

			$tr = $zones | Where-Object { $_.ZoneIndex -eq 1 }
			$tr.X | Should -Be 500
			$tr.Y | Should -Be 0

			$bl = $zones | Where-Object { $_.ZoneIndex -eq 2 }
			$bl.X | Should -Be 0
			$bl.Y | Should -Be 500

			$br = $zones | Where-Object { $_.ZoneIndex -eq 3 }
			$br.X | Should -Be 500
			$br.Y | Should -Be 500
		}

		It "Should apply monitor offset to all zone coordinates" {
			$zones = Get-FancyZoneCoordinates -LayoutName "EvenSplit" -MonitorX 1920 -MonitorY -1080 -MonitorWidth 1000 -MonitorHeight 500 -CustomLayoutsPath $script:TestLayoutsPath

			$left = $zones | Where-Object { $_.ZoneIndex -eq 0 }
			$left.X | Should -Be 1920
			$left.Y | Should -Be -1080
			$left.MonitorX | Should -Be 1920
			$left.MonitorY | Should -Be -1080
		}

		It "Should calculate uneven column splits correctly" {
			$zones = Get-FancyZoneCoordinates -LayoutName "UnevenSplit" -MonitorX 0 -MonitorY 0 -MonitorWidth 3000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			$left = $zones | Where-Object { $_.ZoneIndex -eq 0 }
			$right = $zones | Where-Object { $_.ZoneIndex -eq 1 }

			# 6667/10000 * 3000 = 2000.1 → 2000, 3333/10000 * 3000 = 999.9 → 1000
			$left.Width | Should -Be 2000
			$right.Width | Should -Be 1000
			$right.X | Should -Be 2000
		}

		It "Should handle spanning zones by merging cells" {
			$zones = Get-FancyZoneCoordinates -LayoutName "SpanningLayout" -MonitorX 0 -MonitorY 0 -MonitorWidth 3000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			# Zone 0 spans both rows in column 0
			$zone0 = $zones | Where-Object { $_.ZoneIndex -eq 0 }
			$zone0.Height | Should -Be 1000
			$zone0.Y | Should -Be 0

			# Zone 1 spans columns 1-2 in row 0
			$zone1 = $zones | Where-Object { $_.ZoneIndex -eq 1 }
			$zone1.Height | Should -Be 500
			$zone1.Width | Should -BeGreaterThan ($zone0.Width)
		}

		It "Should apply spacing to zone coordinates when show-spacing is true" {
			$zones = Get-FancyZoneCoordinates -LayoutName "WithSpacing" -MonitorX 0 -MonitorY 0 -MonitorWidth 1000 -MonitorHeight 500 -CustomLayoutsPath $script:TestLayoutsPath

			$left = $zones | Where-Object { $_.ZoneIndex -eq 0 }
			# With spacing=20: X += 10, Width -= 20
			$left.X | Should -Be 10
			$left.Width | Should -Be 480
		}

		It "Should include LayoutName in each zone result" {
			$zones = Get-FancyZoneCoordinates -LayoutName "EvenSplit" -MonitorX 0 -MonitorY 0 -MonitorWidth 1000 -MonitorHeight 500 -CustomLayoutsPath $script:TestLayoutsPath

			$zones | ForEach-Object { $_.LayoutName | Should -Be "EvenSplit" }
		}
	}

	Context "Error Handling" {
		It "Should return null for non-existent layout file" {
			$result = Get-FancyZoneCoordinates -LayoutName "Any" -CustomLayoutsPath "C:\NonExistent\layouts.json" -ErrorAction SilentlyContinue

			$result | Should -BeNullOrEmpty
		}

		It "Should return null for non-existent layout name" {
			$result = Get-FancyZoneCoordinates -LayoutName "NonExistentLayout" -CustomLayoutsPath $script:TestLayoutsPath -ErrorAction SilentlyContinue

			$result | Should -BeNullOrEmpty
		}

		It "Should return null for canvas layout type" {
			$result = Get-FancyZoneCoordinates -LayoutName "CanvasLayout" -CustomLayoutsPath $script:TestLayoutsPath -WarningAction SilentlyContinue

			$result | Should -BeNullOrEmpty
		}
	}
}
