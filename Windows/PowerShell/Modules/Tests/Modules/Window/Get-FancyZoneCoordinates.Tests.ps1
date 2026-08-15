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
					name = "LargeSpacingGrid"
					type = "grid"
					info = @{
						rows                 = 2
						columns              = 2
						'rows-percentage'    = @(5000, 5000)
						'columns-percentage' = @(5000, 5000)
						'cell-child-map'     = @(@(0, 1), @(2, 3))
						'show-spacing'       = $true
						spacing              = 40
					}
				}
				@{
					name = "SpanningWithSpacing"
					type = "grid"
					info = @{
						rows                 = 2
						columns              = 2
						'rows-percentage'    = @(5000, 5000)
						'columns-percentage' = @(5000, 5000)
						'cell-child-map'     = @(@(0, 1), @(0, 2))
						'show-spacing'       = $true
						spacing              = 10
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
					name = "ExactThirds"
					type = "grid"
					info = @{
						rows                 = 1
						columns              = 3
						'rows-percentage'    = @(10000)
						'columns-percentage' = @(3333, 3333, 3334)
						'cell-child-map'     = @(, @(0, 1, 2))
						'show-spacing'       = $false
						spacing              = 0
					}
				}
				@{
					name = "BadPercentCount"
					type = "grid"
					info = @{
						rows                 = 1
						columns              = 3
						'rows-percentage'    = @(10000)
						'columns-percentage' = @(5000, 5000)
						'cell-child-map'     = @(, @(0, 1, 2))
						'show-spacing'       = $false
						spacing              = 0
					}
				}
				@{
					name = "CanvasLayout"
					type = "canvas"
					info = @{
						'ref-width'  = 1000
						'ref-height' = 1000
						# Canvas layouts ignore spacing even when present
						'show-spacing' = $true
						spacing        = 50
						zones          = @(
							@{ X = 0; Y = 0; width = 500; height = 1000 }
							@{ X = 500; Y = 0; width = 500; height = 500 }
						)
					}
				}
				@{
					name = "CanvasBadRef"
					type = "canvas"
					info = @{
						'ref-width'  = 0
						'ref-height' = 1080
						zones        = @(
							@{ X = 0; Y = 0; width = 960; height = 1080 }
						)
					}
				}
				@{
					name = "FocusLayout"
					type = "focus"
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

			# Prefix sums: Floor(6667 * 3000 / 10000) = 2000, Floor(10000 * 3000 / 10000) = 3000
			$left.Width | Should -Be 2000
			$right.Width | Should -Be 1000
			$right.X | Should -Be 2000
		}

		It "Should make uneven percentages sum exactly to the work area (prefix-sum, no lost pixels)" {
			$zones = Get-FancyZoneCoordinates -LayoutName "ExactThirds" -MonitorX 0 -MonitorY 0 -MonitorWidth 3440 -MonitorHeight 1440 -CustomLayoutsPath $script:TestLayoutsPath

			$zones.Count | Should -Be 3
			# Edges: Floor(3333*3440/10000)=1146, Floor(6666*3440/10000)=2293, Floor(10000*3440/10000)=3440
			$sorted = $zones | Sort-Object ZoneIndex
			$sorted[0].Width | Should -Be 1146
			$sorted[1].X | Should -Be 1146
			$sorted[1].Width | Should -Be 1147
			$sorted[2].X | Should -Be 2293
			$sorted[2].Width | Should -Be 1147

			# The three widths cover the full work area with zero remainder
			($sorted | Measure-Object -Property Width -Sum).Sum | Should -Be 3440
			$sorted[2].X + $sorted[2].Width | Should -Be 3440
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

		It "Should include LayoutName in each zone result" {
			$zones = Get-FancyZoneCoordinates -LayoutName "EvenSplit" -MonitorX 0 -MonitorY 0 -MonitorWidth 1000 -MonitorHeight 500 -CustomLayoutsPath $script:TestLayoutsPath

			$zones | ForEach-Object { $_.LayoutName | Should -Be "EvenSplit" }
		}
	}

	Context "Spacing (FancyZones model: full on outer edges, Floor(spacing/2) per interior edge)" {
		It "Should inset outer edges by the full spacing and interior edges by half" {
			$zones = Get-FancyZoneCoordinates -LayoutName "WithSpacing" -MonitorX 0 -MonitorY 0 -MonitorWidth 1000 -MonitorHeight 500 -CustomLayoutsPath $script:TestLayoutsPath

			# spacing=20, half=10
			$left = $zones | Where-Object { $_.ZoneIndex -eq 0 }
			$left.X | Should -Be 20        # outer left edge: full spacing
			$left.Y | Should -Be 20        # outer top edge: full spacing
			$left.Width | Should -Be 470   # 500 - 20 (outer) - 10 (interior)
			$left.Height | Should -Be 460  # 500 - 20 (top) - 20 (bottom)

			$right = $zones | Where-Object { $_.ZoneIndex -eq 1 }
			$right.X | Should -Be 510      # 500 + 10 (interior)
			$right.Width | Should -Be 470  # 980 - 510
			$right.Height | Should -Be 460
		}

		It "Should apply the model consistently on a 2x2 grid with large spacing" {
			$zones = Get-FancyZoneCoordinates -LayoutName "LargeSpacingGrid" -MonitorX 0 -MonitorY 0 -MonitorWidth 1000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			# spacing=40, half=20
			$tl = $zones | Where-Object { $_.ZoneIndex -eq 0 }
			$tl.X | Should -Be 40
			$tl.Y | Should -Be 40
			$tl.Width | Should -Be 440   # 480 - 40
			$tl.Height | Should -Be 440

			$tr = $zones | Where-Object { $_.ZoneIndex -eq 1 }
			$tr.X | Should -Be 520       # 500 + 20
			$tr.Width | Should -Be 440   # 960 - 520
			$tr.Y | Should -Be 40

			$br = $zones | Where-Object { $_.ZoneIndex -eq 3 }
			$br.X | Should -Be 520
			$br.Y | Should -Be 520
			$br.Width | Should -Be 440
			$br.Height | Should -Be 440

			# Interior gap between adjacent zones is 2 * Floor(spacing/2) = 40
			($tr.X - ($tl.X + $tl.Width)) | Should -Be 40
		}

		It "Should let a spanning zone absorb the interior spacing it covers" {
			$zones = Get-FancyZoneCoordinates -LayoutName "SpanningWithSpacing" -MonitorX 0 -MonitorY 0 -MonitorWidth 1000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			# spacing=10, half=5. Zone 0 spans both rows in column 0:
			# top/bottom are outer edges (full 10), so the row boundary gap is absorbed.
			$zone0 = $zones | Where-Object { $_.ZoneIndex -eq 0 }
			$zone0.Y | Should -Be 10
			$zone0.Height | Should -Be 980  # 1000 - 10 - 10, no interior deduction
			$zone0.X | Should -Be 10
			$zone0.Width | Should -Be 485   # 495 - 10

			# Zones 1 and 2 are stacked right: each loses half spacing at the row boundary
			$zone1 = $zones | Where-Object { $_.ZoneIndex -eq 1 }
			$zone1.Y | Should -Be 10
			$zone1.Height | Should -Be 485  # 495 - 10
			$zone2 = $zones | Where-Object { $_.ZoneIndex -eq 2 }
			$zone2.Y | Should -Be 505       # 500 + 5
			$zone2.Height | Should -Be 485  # 990 - 505
		}

		It "Should apply no spacing when show-spacing is false" {
			$zones = Get-FancyZoneCoordinates -LayoutName "EvenSplit" -MonitorX 0 -MonitorY 0 -MonitorWidth 1000 -MonitorHeight 500 -CustomLayoutsPath $script:TestLayoutsPath

			$left = $zones | Where-Object { $_.ZoneIndex -eq 0 }
			$left.X | Should -Be 0
			$left.Width | Should -Be 500
		}
	}

	Context "Canvas Layouts" {
		It "Should scale canvas zones from ref space to the monitor work area" {
			$zones = Get-FancyZoneCoordinates -LayoutName "CanvasLayout" -MonitorX 0 -MonitorY 0 -MonitorWidth 2000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			$zones.Count | Should -Be 2

			# ref 1000x1000 -> monitor 2000x1000: X/Width doubled, Y/Height unchanged
			$zone0 = $zones | Where-Object { $_.ZoneIndex -eq 0 }
			$zone0.X | Should -Be 0
			$zone0.Y | Should -Be 0
			$zone0.Width | Should -Be 1000
			$zone0.Height | Should -Be 1000

			$zone1 = $zones | Where-Object { $_.ZoneIndex -eq 1 }
			$zone1.X | Should -Be 1000
			$zone1.Y | Should -Be 0
			$zone1.Width | Should -Be 1000
			$zone1.Height | Should -Be 500
		}

		It "Should assign zone indices by array position and ignore spacing" {
			# The CanvasLayout fixture carries show-spacing=true / spacing=50 - the exact
			# scaled rects above prove spacing was not applied.
			$zones = Get-FancyZoneCoordinates -LayoutName "CanvasLayout" -MonitorX 0 -MonitorY 0 -MonitorWidth 1000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			@($zones | ForEach-Object { $_.ZoneIndex }) | Should -Be @(0, 1)
			$zone0 = $zones | Where-Object { $_.ZoneIndex -eq 0 }
			$zone0.X | Should -Be 0
			$zone0.Width | Should -Be 500
		}

		It "Should apply monitor offset to canvas zones" {
			$zones = Get-FancyZoneCoordinates -LayoutName "CanvasLayout" -MonitorX 100 -MonitorY -200 -MonitorWidth 1000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			$zone1 = $zones | Where-Object { $_.ZoneIndex -eq 1 }
			$zone1.X | Should -Be 600
			$zone1.Y | Should -Be -200
		}

		It "Should return null for a canvas layout with invalid ref dimensions" {
			$result = Get-FancyZoneCoordinates -LayoutName "CanvasBadRef" -CustomLayoutsPath $script:TestLayoutsPath -ErrorAction SilentlyContinue

			$result | Should -BeNullOrEmpty
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

		It "Should return null with a clear error for a malformed grid definition" {
			$result = Get-FancyZoneCoordinates -LayoutName "BadPercentCount" -CustomLayoutsPath $script:TestLayoutsPath -ErrorAction SilentlyContinue -ErrorVariable coordErrors

			$result | Should -BeNullOrEmpty
			@($coordErrors | Where-Object { $_.ToString() -match "columns-percentage" }).Count | Should -BeGreaterThan 0
		}

		It "Should return null for unsupported layout types" {
			$result = Get-FancyZoneCoordinates -LayoutName "FocusLayout" -CustomLayoutsPath $script:TestLayoutsPath -WarningAction SilentlyContinue

			$result | Should -BeNullOrEmpty
		}
	}
}
