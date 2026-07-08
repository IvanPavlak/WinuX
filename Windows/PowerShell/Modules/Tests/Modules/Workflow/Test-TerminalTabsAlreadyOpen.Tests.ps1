#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Test-TerminalTabsAlreadyOpen.ps1"
}

Describe "Test-TerminalTabsAlreadyOpen" {
	BeforeEach {
		Mock Write-Host { }
	}

	It "returns AllOpen false when Windows Terminal is not running" {
		Mock Get-Process { @() }

		$result = Test-TerminalTabsAlreadyOpen -ExpectedTabNames @("WinuX.Root") -ProjectName "WinuX"

		$result.AllOpen | Should -BeFalse
		$result.FoundTabs | Should -BeNullOrEmpty
	}

	It "returns AllOpen false when exception is thrown" {
		Mock Get-Process { throw "boom" }

		$result = Test-TerminalTabsAlreadyOpen -ExpectedTabNames @("WinuX.Root") -ProjectName "WinuX"

		$result.AllOpen | Should -BeFalse
		$result.FoundTabs | Should -BeNullOrEmpty
	}
}
