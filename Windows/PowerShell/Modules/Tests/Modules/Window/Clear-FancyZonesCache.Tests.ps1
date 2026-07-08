#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Clear-FancyZonesCache.ps1"
}

Describe "Clear-FancyZonesCache" {
	It "resets FancyZones cache fields" {
		$script:FancyZonesCache = @{
			Data      = @{ Layouts = @() }
			Path      = "C:\\Temp\\zones.json"
			Timestamp = [datetime]::Now
		}

		Clear-FancyZonesCache

		$script:FancyZonesCache.Data | Should -BeNullOrEmpty
		$script:FancyZonesCache.Path | Should -BeNullOrEmpty
		$script:FancyZonesCache.Timestamp | Should -Be ([datetime]::MinValue)
	}
}
