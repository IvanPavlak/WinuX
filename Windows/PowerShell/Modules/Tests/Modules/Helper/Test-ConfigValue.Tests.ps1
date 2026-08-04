#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
}

Describe "Test-ConfigValue" {
	Context "Unconfigured values" {
		It "Should be false for null" {
			Test-ConfigValue $null | Should -BeFalse
		}

		It "Should be false for an empty string" {
			Test-ConfigValue "" | Should -BeFalse
		}

		It "Should be false for a whitespace-only string" {
			Test-ConfigValue "   " | Should -BeFalse
		}

		It "Should be false for an empty array" {
			Test-ConfigValue @() | Should -BeFalse
		}

		It "Should be false for an empty hashtable (which is truthy in PowerShell)" {
			Test-ConfigValue @{} | Should -BeFalse
		}

		It "Should be false for an empty ordered dictionary" {
			Test-ConfigValue ([ordered]@{}) | Should -BeFalse
		}
	}

	Context "Configured values" {
		It "Should be true for a non-empty string" {
			Test-ConfigValue "Ubuntu" | Should -BeTrue
		}

		It "Should be true for a non-empty array" {
			Test-ConfigValue @("one") | Should -BeTrue
		}

		It "Should be true for a non-empty hashtable" {
			Test-ConfigValue @{ Key = "Value" } | Should -BeTrue
		}

		It "Should be true for zero (a real numeric value)" {
			Test-ConfigValue 0 | Should -BeTrue
		}

		It "Should be true for false (a real boolean value)" {
			Test-ConfigValue $false | Should -BeTrue
		}
	}
}
