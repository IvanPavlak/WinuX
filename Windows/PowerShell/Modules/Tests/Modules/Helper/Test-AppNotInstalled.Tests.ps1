#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Test-AppNotInstalled.ps1"
}

Describe "Test-AppNotInstalled" {
	It "returns true when app package is missing" {
		Mock Get-AppxPackage { $null }

		$result = Test-AppNotInstalled -appName "WindowsTerminal"

		$result | Should -BeTrue
	}

	It "returns false when app package exists" {
		Mock Get-AppxPackage { @{ Name = "WindowsTerminal" } }

		$result = Test-AppNotInstalled -appName "WindowsTerminal"

		$result | Should -BeFalse
	}
}
