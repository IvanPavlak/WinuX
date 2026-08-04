#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"
}

Describe "Confirm-ConfigValue" {
	BeforeEach {
		Mock Write-LogWarning { }
	}

	Context "Configured values" {
		It "Should return true and stay silent" {
			Confirm-ConfigValue "Ubuntu" "should not appear" | Should -BeTrue

			Should -Invoke Write-LogWarning -Times 0
		}

		It "Should return true for a non-empty hashtable" {
			Confirm-ConfigValue @{ Key = "Value" } "should not appear" | Should -BeTrue

			Should -Invoke Write-LogWarning -Times 0
		}
	}

	Context "Unconfigured values" {
		It "Should return false and write the given warning" {
			Confirm-ConfigValue "" "Themes not configured - leaving system theme as-is!" | Should -BeFalse

			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match "Themes not configured" }
		}

		It "Should return false for an empty hashtable (truthy in PowerShell)" {
			Confirm-ConfigValue @{} "section not configured" | Should -BeFalse

			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}

		It "Should return false for null" {
			Confirm-ConfigValue $null "value not configured" | Should -BeFalse

			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}

		It "Should suppress the warning with -Quiet but keep the false result" {
			Confirm-ConfigValue @() "should not appear" -Quiet | Should -BeFalse

			Should -Invoke Write-LogWarning -Times 0
		}
	}
}
