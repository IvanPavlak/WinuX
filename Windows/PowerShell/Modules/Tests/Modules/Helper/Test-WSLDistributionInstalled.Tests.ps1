#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Test-WSLDistributionInstalled.ps1"
}

Describe "Test-WSLDistributionInstalled" {
	BeforeEach {
		$script:Configuration = @{ DefaultWSLDistribution = "Ubuntu" }
		Mock Write-Host { }
		Mock Write-LogError { }
		Mock Write-LogDebug { }
		Mock wsl { @("Windows Subsystem for Linux Distributions:", "Ubuntu (Default)") }
	}

	It "returns true when configured distribution is present" {
		$result = Test-WSLDistributionInstalled

		$result | Should -BeTrue
	}

	It "returns false quietly when no default distribution is configured" {
		$script:Configuration = @{ }

		$result = Test-WSLDistributionInstalled

		# An unconfigured distribution is the empty-base default, not an error -
		# probes like SymbolicLinkMaker hit this on every vanilla run.
		$result | Should -BeFalse
		Should -Invoke Write-LogError -Times 0
	}
}
