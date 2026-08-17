#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Clear-MonitorCache.ps1"
}

Describe "Clear-MonitorCache" {
	It "resets monitor cache values" {
		$script:MonitorCache = @{
			Monitors    = @("M1")
			Timestamp   = [datetime]::Now
			Fingerprint = "2|0,0,3840,1080"
			MaxAgeSec   = 60
		}

		Clear-MonitorCache

		$script:MonitorCache.Monitors | Should -BeNullOrEmpty
		$script:MonitorCache.Timestamp | Should -Be ([datetime]::MinValue)
	}

	It "clears the display-topology fingerprint too" {
		# Leaving it behind would have the next call compare fresh monitor data against a
		# signature captured before the display change that prompted the clear.
		$script:MonitorCache = @{
			Monitors    = @("M1")
			Timestamp   = [datetime]::Now
			Fingerprint = "2|0,0,3840,1080"
			MaxAgeSec   = 60
		}

		Clear-MonitorCache

		$script:MonitorCache.Fingerprint | Should -BeNullOrEmpty
	}
}
