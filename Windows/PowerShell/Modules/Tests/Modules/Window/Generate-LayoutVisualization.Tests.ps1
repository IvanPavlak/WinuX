#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Generate-LayoutVisualization" {
	BeforeAll {
		# Create test layouts JSON
		$script:TestLayoutsPath = Join-Path $TestDrive "test-custom-layouts.json"
		$testLayouts = @{
			'custom-layouts' = @(
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
					name = "CanvasLayout"
					type = "canvas"
					info = @{
						'ref-width'  = 1920
						'ref-height' = 1080
						zones        = @(
							@{ X = 0; Y = 0; width = 960; height = 1080 }
						)
					}
				}
			)
		}
		$testLayouts | ConvertTo-Json -Depth 10 | Set-Content $script:TestLayoutsPath

		# Set up global Configuration
		$global:Configuration = @{
			ZoneNameMappings = @{
				"One" = @{
					"Left"  = 0
					"Right" = 1
				}
			}
		}
	}

	BeforeEach {
		Mock Write-Host { }
		Mock Write-Error { }
	}

	Context "When generating for a valid grid layout" {
		It "Should return header with desktop, monitor, and layout info" {
			$windows = @(
				[PSCustomObject]@{ ProcessName = "Code"; WindowTitle = $null; Zone = "Left" }
			)

			$result = Generate-LayoutVisualization -LayoutType "One" -Windows $windows -DesktopNumber 1 -MonitorName "Primary" -LayoutsJsonPath $script:TestLayoutsPath

			$result | Should -Not -BeNullOrEmpty
			$result | Should -Match "VIRTUAL DESKTOP 1"
			$result | Should -Match "Primary"
			$result | Should -Match "One"
		}

		It "Should include process names in zone content" {
			$windows = @(
				[PSCustomObject]@{ ProcessName = "Code"; WindowTitle = $null; Zone = "Left" }
				[PSCustomObject]@{ ProcessName = "Firefox"; WindowTitle = $null; Zone = "Right" }
			)

			$result = Generate-LayoutVisualization -LayoutType "One" -Windows $windows -DesktopNumber 1 -MonitorName "Primary" -LayoutsJsonPath $script:TestLayoutsPath

			$result | Should -Match "Code"
			$result | Should -Match "Firefox"
		}

		It "Should include window title when provided" {
			$windows = @(
				[PSCustomObject]@{ ProcessName = "Firefox"; WindowTitle = "*YouTube*"; Zone = "Left" }
			)

			$result = Generate-LayoutVisualization -LayoutType "One" -Windows $windows -DesktopNumber 1 -MonitorName "Primary" -LayoutsJsonPath $script:TestLayoutsPath

			$result | Should -Match "Firefox"
			$result | Should -Match "YouTube"
		}
	}

	Context "When layout is not found" {
		It "Should return error message for missing layout" {
			$result = Generate-LayoutVisualization -LayoutType "Nonexistent" -Windows @() -DesktopNumber 1 -MonitorName "Primary" -LayoutsJsonPath $script:TestLayoutsPath

			$result | Should -Match "not found"
		}
	}

	Context "When layout is non-grid type" {
		It "Should return unsupported message for canvas layout" {
			$result = Generate-LayoutVisualization -LayoutType "CanvasLayout" -Windows @() -DesktopNumber 1 -MonitorName "Primary" -LayoutsJsonPath $script:TestLayoutsPath

			$result | Should -Match "not supported"
		}
	}

	AfterAll {
		Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
	}
}
