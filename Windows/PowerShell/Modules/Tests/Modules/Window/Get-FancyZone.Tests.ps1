#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Get-FancyZone" {
	BeforeAll {
		# Create test layouts JSON
		$script:TestLayoutsPath = Join-Path $TestDrive "test-custom-layouts.json"
		$testLayouts = @{
			'custom-layouts' = @(
				@{
					name = "Zero"
					type = "grid"
					info = @{
						rows                 = 1
						columns              = 1
						'rows-percentage'    = @(10000)
						'columns-percentage' = @(10000)
						'cell-child-map'     = @(, @(, 0))
						'show-spacing'       = $false
						spacing              = 0
					}
				}
				@{
					name = "One"
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
					name = "Four"
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
			)
		}
		$testLayouts | ConvertTo-Json -Depth 10 | Set-Content $script:TestLayoutsPath

		# Set up global Configuration with ZoneNameMappings
		$global:Configuration = @{
			ZoneNameMappings = @{
				"Zero" = @{
					"Full"       = 0
					"Fullscreen" = 0
				}
				"One"  = @{
					"Left"  = 0
					"Right" = 1
				}
				"Four" = @{
					"Top-Left"     = 0
					"Top-Right"    = 1
					"Bottom-Left"  = 2
					"Bottom-Right" = 3
				}
			}
		}
	}

	BeforeEach {
		Mock Write-Host { } -ModuleName Window
		Mock Write-Error { } -ModuleName Window
	}

	Context "When resolving zone by name" {
		It "Should return correct zone for 'Left' in layout One" {
			$result = Get-FancyZone -LayoutName "One" -ZoneName "Left" -MonitorX 0 -MonitorY 0 -MonitorWidth 2000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			$result | Should -Not -BeNullOrEmpty
			$result.ZoneIndex | Should -Be 0
			$result.X | Should -Be 0
			$result.Width | Should -Be 1000
			$result.ZoneName | Should -Be "Left"
		}

		It "Should return correct zone for 'Right' in layout One" {
			$result = Get-FancyZone -LayoutName "One" -ZoneName "Right" -MonitorX 0 -MonitorY 0 -MonitorWidth 2000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			$result | Should -Not -BeNullOrEmpty
			$result.ZoneIndex | Should -Be 1
			$result.X | Should -Be 1000
			$result.Width | Should -Be 1000
			$result.ZoneName | Should -Be "Right"
		}

		It "Should apply monitor offset" {
			$result = Get-FancyZone -LayoutName "One" -ZoneName "Left" -MonitorX 1920 -MonitorY -1080 -MonitorWidth 2000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			$result.X | Should -Be 1920
			$result.Y | Should -Be -1080
		}

		It "Should return correct zone for 'Bottom-Right' in layout Four" {
			$result = Get-FancyZone -LayoutName "Four" -ZoneName "Bottom-Right" -MonitorX 0 -MonitorY 0 -MonitorWidth 2000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			$result.ZoneIndex | Should -Be 3
			$result.X | Should -Be 1000
			$result.Y | Should -Be 500
			$result.Width | Should -Be 1000
			$result.Height | Should -Be 500
		}
	}

	Context "TotalZoneCount (single-zone detection)" {
		# The snap pipeline branches on this member: a single-zone layout has no neighbouring
		# zone for FancyZones' relative Win+Arrow, so Snap-AllWindows places it directly.
		It "Should report 1 for the single-zone Zero layout" {
			$result = Get-FancyZone -LayoutName "Zero" -ZoneName "Fullscreen" -MonitorX 0 -MonitorY 0 -MonitorWidth 2000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			$result | Should -Not -BeNullOrEmpty
			$result.TotalZoneCount | Should -Be 1
		}

		It "Should count zones from the layout definition, not the name mappings" {
			# "Full" and "Fullscreen" both map to index 0 - two names, still one zone.
			$result = Get-FancyZone -LayoutName "Zero" -ZoneName "Full" -MonitorX 0 -MonitorY 0 -MonitorWidth 2000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			$result.TotalZoneCount | Should -Be 1
		}

		It "Should report the full zone count for multi-zone layouts" {
			$one = Get-FancyZone -LayoutName "One" -ZoneName "Left" -MonitorX 0 -MonitorY 0 -MonitorWidth 2000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath
			$four = Get-FancyZone -LayoutName "Four" -ZoneName "Bottom-Right" -MonitorX 0 -MonitorY 0 -MonitorWidth 2000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			$one.TotalZoneCount | Should -Be 2
			$four.TotalZoneCount | Should -Be 4
		}
	}

	Context "When zone name is invalid" {
		It "Should return null for unknown zone name" {
			$result = Get-FancyZone -LayoutName "One" -ZoneName "Center" -MonitorX 0 -MonitorY 0 -MonitorWidth 2000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			$result | Should -BeNullOrEmpty
			Should -Invoke Write-Error -ModuleName Window
		}
	}

	Context "When layout name is invalid" {
		It "Should return null for unknown layout" {
			$result = Get-FancyZone -LayoutName "Nonexistent" -ZoneName "Left" -MonitorX 0 -MonitorY 0 -MonitorWidth 2000 -MonitorHeight 1000 -CustomLayoutsPath $script:TestLayoutsPath

			$result | Should -BeNullOrEmpty
			Should -Invoke Write-Error -ModuleName Window
		}
	}

	AfterAll {
		Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
	}
}
