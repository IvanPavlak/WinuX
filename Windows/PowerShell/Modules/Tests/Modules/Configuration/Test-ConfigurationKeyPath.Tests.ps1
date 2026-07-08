#Requires -Modules Pester

BeforeAll {
	$ConfigFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigFunctionsPath\Test-ConfigurationKeyPath.ps1"
}

Describe "Test-ConfigurationKeyPath" {
	It "returns true when the full path exists and resolves to a non-empty value" {
		$config = @{ GitConfig = @{ UserName = 'ExampleUser' } }

		$result = Test-ConfigurationKeyPath -Table $config -Path @('GitConfig', 'UserName')

		$result | Should -BeTrue
	}

	It "returns false when any path segment is missing" {
		$config = @{ GitConfig = @{ } }

		$result = Test-ConfigurationKeyPath -Table $config -Path @('GitConfig', 'UserName')

		$result | Should -BeFalse
	}

	It "returns false when the final value is an empty string" {
		$config = @{ GitConfig = @{ UserName = '' } }

		$result = Test-ConfigurationKeyPath -Table $config -Path @('GitConfig', 'UserName')

		$result | Should -BeFalse
	}
}
