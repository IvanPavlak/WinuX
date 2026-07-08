#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Clear-MonitorCache.ps1"
}

Describe "Clear-MonitorCache" {
	It "resets monitor cache values" {
		$script:MonitorCache = @{
			Monitors  = @("M1")
			Timestamp = [datetime]::Now
			MaxAgeSec = 60
		}

		Clear-MonitorCache

		$script:MonitorCache.Monitors | Should -BeNullOrEmpty
		$script:MonitorCache.Timestamp | Should -Be ([datetime]::MinValue)
	}
}
