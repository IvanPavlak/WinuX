#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Visualize-Layouts" {
	BeforeAll {
		# Create test layouts JSON
		$script:TestLayoutsJsonPath = Join-Path $TestDrive "Windows\FancyZones\custom-layouts.json"
		$fancyZonesDir = Split-Path $script:TestLayoutsJsonPath -Parent
		New-Item -ItemType Directory -Path $fancyZonesDir -Force | Out-Null

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
			)
		}
		$testLayouts | ConvertTo-Json -Depth 10 | Set-Content $script:TestLayoutsJsonPath

		# Create test layout .psd1 file
		$script:TestLayoutsDir = Join-Path $TestDrive "Layouts"
		New-Item -ItemType Directory -Path $script:TestLayoutsDir -Force | Out-Null

		$layoutContent = @'
@{
	Monitors = @{
		Primary = @{
			VirtualDesktopLayouts = @{
				1 = "One"
			}
		}
	}
	Layout = @(
		@{ ProcessName = "Code"; Zone = "Left"; Monitor = "Primary"; DesktopNumber = 1 }
		@{ ProcessName = "Firefox"; Zone = "Right"; Monitor = "Primary"; DesktopNumber = 1 }
	)
}
'@
		Set-Content -Path (Join-Path $script:TestLayoutsDir "TestLayout.psd1") -Value $layoutContent

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
		Mock Write-Host { } -ModuleName Window
		Mock Write-Error { } -ModuleName Window
		Mock Write-LogError { } -ModuleName Window
		Mock Write-LogWarning { } -ModuleName Window
	}

	Context "When displaying available layout types" {
		It "Should display sorted layout types" {
			$global:RepoRoot = $TestDrive

			Visualize-Layouts -DisplayAvailableLayouts

			Should -Invoke Write-Host -ModuleName Window
		}
	}

	Context "When configuration is missing" {
		It "Should show error when Configuration is null" {
			$savedConfig = $global:Configuration
			$global:Configuration = $null

			Visualize-Layouts -DisplayAvailableLayouts

			Should -Invoke Write-LogError -ModuleName Window -ParameterFilter { $Message -match "configuration not loaded" }

			$global:Configuration = $savedConfig
		}
	}

	Context "When no layout files exist" {
		It "Should show message when layouts directory is missing" {
			Mock Get-ChildItem { @() } -ModuleName Window -ParameterFilter { $Filter -eq "*.psd1" }

			Visualize-Layouts -All

			Should -Invoke Write-LogWarning -ModuleName Window -ParameterFilter { $Message -match "not found|No layout files" }
		}
	}

	AfterAll {
		Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
		Remove-Variable -Name RepoRoot -Scope Global -ErrorAction SilentlyContinue
	}
}
