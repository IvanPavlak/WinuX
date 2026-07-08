#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Get-LayoutDefinition" {
	BeforeAll {
		# Create a temporary test layouts file
		$script:TestLayoutsPath = Join-Path $TestDrive "test-custom-layouts.json"
		$testLayouts = @{
			'custom-layouts' = @(
				@{
					name = "TestLayout1"
					type = "grid"
					info = @{
						rows                 = 2
						columns              = 2
						'rows-percentage'    = @(5000, 5000)
						'columns-percentage' = @(5000, 5000)
						'cell-child-map'     = @(@(0, 1), @(2, 3))
					}
				}
				@{
					name = "TestLayout2"
					type = "canvas"
					info = @{}
				}
				@{
					name = "VerticalSplit"
					type = "grid"
					info = @{
						rows                 = 1
						columns              = 2
						'rows-percentage'    = @(10000)
						'columns-percentage' = @(5000, 5000)
						'cell-child-map'     = @(@(0, 1))
					}
				}
			)
		}
		$testLayouts | ConvertTo-Json -Depth 10 | Set-Content $script:TestLayoutsPath
	}

	Context "Loading Layouts" {
		It "Should load an existing layout by name" {
			$result = Get-LayoutDefinition -LayoutsJsonPath $script:TestLayoutsPath -LayoutName "TestLayout1"

			$result | Should -Not -BeNullOrEmpty
			$result.name | Should -Be "TestLayout1"
			$result.type | Should -Be "grid"
		}

		It "Should return null for non-existent layout" {
			$result = Get-LayoutDefinition -LayoutsJsonPath $script:TestLayoutsPath -LayoutName "NonExistent"

			$result | Should -BeNullOrEmpty
		}

		It "Should load layout with correct grid structure" {
			$result = Get-LayoutDefinition -LayoutsJsonPath $script:TestLayoutsPath -LayoutName "TestLayout1"

			$result.info.rows | Should -Be 2
			$result.info.columns | Should -Be 2
			$result.info.'cell-child-map'.Count | Should -Be 2
		}

		It "Should load different layouts independently" {
			$layout1 = Get-LayoutDefinition -LayoutsJsonPath $script:TestLayoutsPath -LayoutName "TestLayout1"
			$layout2 = Get-LayoutDefinition -LayoutsJsonPath $script:TestLayoutsPath -LayoutName "VerticalSplit"

			$layout1.name | Should -Be "TestLayout1"
			$layout2.name | Should -Be "VerticalSplit"
			$layout1.info.rows | Should -Be 2
			$layout2.info.rows | Should -Be 1
		}
	}

	Context "Error Handling" {
		It "Should return null for non-existent file" {
			$result = Get-LayoutDefinition -LayoutsJsonPath "C:\NonExistent\path.json" -LayoutName "Any" -ErrorAction SilentlyContinue

			$result | Should -BeNullOrEmpty
		}
	}
}
