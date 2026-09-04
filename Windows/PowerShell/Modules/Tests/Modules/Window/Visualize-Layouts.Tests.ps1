#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force

	function script:Get-FirstMatchingLineIndex {
		param ([object[]]$Lines, [string]$Pattern)
		for ($i = 0; $i -lt $Lines.Count; $i++) {
			if ($Lines[$i] -match $Pattern) { return $i }
		}
		return -1
	}
}

Describe "Visualize-Layouts" {
	BeforeAll {
		# Create test layouts JSON. File order: One, Beta, Free - LayoutNumbers puts
		# Beta on hotkey 0 and One on hotkey 1, and Free has no LayoutNumbers entry,
		# so the display order must be Beta, One, Free.
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
				@{
					name = "Beta"
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
					name = "Free"
					type = "canvas"
					info = @{
						'ref-width'  = 1000
						'ref-height' = 1000
						zones        = @(
							@{ X = 0; Y = 0; width = 500; height = 1000 }
						)
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
				"One"  = @{
					"Left"  = 0
					"Right" = 1
				}
				"Beta" = @{
					"Full" = 0
				}
			}
			LayoutNumbers    = @{
				"Beta" = 0
				"One"  = 1
			}
		}
	}

	BeforeEach {
		$script:HostLines = @()
		Mock Write-Host { $script:HostLines += , [string]$Object } -ModuleName Window
		Mock Write-Error { } -ModuleName Window
		Mock Write-LogError { } -ModuleName Window
		Mock Write-LogWarning { } -ModuleName Window
		Mock Get-FancyZonesLayoutsPath { $script:TestLayoutsJsonPath } -ModuleName Window
	}

	Context "When displaying available layout types" {
		It "Should display layouts ordered by LayoutNumbers hotkey, then unlisted layouts in file order" {
			Visualize-Layouts -DisplayAvailableLayouts

			Should -Invoke Write-Host -ModuleName Window

			$betaIndex = Get-FirstMatchingLineIndex -Lines $script:HostLines -Pattern "\[Beta\]"
			$oneIndex = Get-FirstMatchingLineIndex -Lines $script:HostLines -Pattern "\[One\]"
			$freeIndex = Get-FirstMatchingLineIndex -Lines $script:HostLines -Pattern "\[Free\]"

			$betaIndex | Should -BeGreaterOrEqual 0
			$oneIndex | Should -BeGreaterThan $betaIndex
			$freeIndex | Should -BeGreaterThan $oneIndex
		}

		It "Should render canvas layouts as a textual zone listing" {
			Visualize-Layouts -DisplayAvailableLayouts

			@($script:HostLines | Where-Object { $_ -match "Zone 0.*x=0% y=0% w=50% h=100%" }).Count | Should -BeGreaterThan 0
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

	Context "When given the layout file path directly" {
		# Set-WorkspaceWindowLayout hands over the file it has just applied; the recursive scan
		# of the Layouts tree (0.1 to 0.7 s per open) is for finding a file by name or the menu.
		It "Should render the file without scanning the Layouts tree" {
			Mock Get-ChildItem { @() } -ModuleName Window -ParameterFilter { $Filter -eq "*.psd1" }

			Visualize-Layouts -LayoutPath (Join-Path $script:TestLayoutsDir "TestLayout.psd1")

			Should -Invoke Get-ChildItem -ModuleName Window -Times 0 -ParameterFilter { $Filter -eq "*.psd1" }
			@($script:HostLines | Where-Object { $_ -match "\[TestLayout\]" }).Count | Should -BeGreaterThan 0
		}

		It "Should report a missing file instead of scanning" {
			Visualize-Layouts -LayoutPath (Join-Path $script:TestLayoutsDir "Missing.psd1")

			Should -Invoke Write-LogError -ModuleName Window -ParameterFilter { $Message -match "Layout file not found" }
		}
	}

	AfterAll {
		Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
	}
}
