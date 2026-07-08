#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Get-CachedFancyZonesLayouts" {
	BeforeAll {
		$script:CacheTestPath = Join-Path $TestDrive "cache-test-layouts.json"
		$testContent = @{
			'custom-layouts' = @(
				@{ name = "CachedLayout"; type = "grid"; info = @{ rows = 1; columns = 1 } }
			)
		}
		$testContent | ConvertTo-Json -Depth 10 | Set-Content $script:CacheTestPath
	}

	Context "Caching Behavior" {
		It "Should load layout from file" {
			$result = Get-CachedFancyZonesLayouts -LayoutsJsonPath $script:CacheTestPath

			$result | Should -Not -BeNullOrEmpty
			$result.'custom-layouts'[0].name | Should -Be "CachedLayout"
		}

		It "Should return null for non-existent file" {
			$result = Get-CachedFancyZonesLayouts -LayoutsJsonPath "C:\NonExistent\layouts.json"

			$result | Should -BeNullOrEmpty
		}
	}
}
