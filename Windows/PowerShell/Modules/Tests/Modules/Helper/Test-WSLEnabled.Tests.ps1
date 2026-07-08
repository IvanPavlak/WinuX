#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Test-WSLEnabled.ps1"
}

Describe "Test-WSLEnabled" {
	BeforeEach {
		Mock wsl { "WSL is not installed" }
	}

	It "returns false when WSL is not installed" {
		$result = Test-WSLEnabled

		$result | Should -BeFalse
	}

	It "returns true when WSL status output indicates availability" {
		Mock wsl { "Default Distribution: Ubuntu" }

		$result = Test-WSLEnabled

		$result | Should -BeTrue
	}
}
