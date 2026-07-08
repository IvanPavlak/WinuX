#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Test-RegistryValue.ps1"
}

Describe "Test-RegistryValue" {
	Context "Registry Value Matching" {
		It "Should return true when registry value matches expected value" {
			Mock Get-ItemProperty {
				[PSCustomObject]@{ TestValue = "ExpectedData" }
			}

			$result = Test-RegistryValue -Path "HKLM:\SOFTWARE\Test" -Name "TestValue" -ExpectedValue "ExpectedData"

			$result | Should -Be $true
		}

		It "Should return false when registry value does not match" {
			Mock Get-ItemProperty {
				[PSCustomObject]@{ TestValue = "DifferentData" }
			}

			$result = Test-RegistryValue -Path "HKLM:\SOFTWARE\Test" -Name "TestValue" -ExpectedValue "ExpectedData"

			$result | Should -Be $false
		}
	}

	Context "Non-Existent Registry Paths" {
		It "Should return false when registry path does not exist" {
			$result = Test-RegistryValue -Path "HKLM:\SOFTWARE\NonExistent_Test_Path_12345" -Name "TestValue" -ExpectedValue "anything"

			$result | Should -Be $false
		}

		It "Should return false when registry name does not exist" {
			Mock Get-ItemProperty { throw "Property not found" }

			$result = Test-RegistryValue -Path "HKLM:\SOFTWARE\Test" -Name "NonExistentValue" -ExpectedValue "anything"

			$result | Should -Be $false
		}
	}
}
