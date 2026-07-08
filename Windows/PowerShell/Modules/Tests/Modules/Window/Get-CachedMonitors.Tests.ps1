#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-CachedMonitors.ps1"
}

Describe "Get-CachedMonitors" {
	BeforeEach {
		Mock Ensure-WindowsFormsLoaded { }
	}

	It "returns cached monitor data when cache is still valid" {
		$cached = @("MonitorA")
		$script:MonitorCache = @{
			Monitors  = $cached
			Timestamp = [datetime]::Now
			MaxAgeSec = 9999
		}

		$result = Get-CachedMonitors

		$result | Should -Be $cached
		Should -Invoke Ensure-WindowsFormsLoaded -Times 0
	}
}
