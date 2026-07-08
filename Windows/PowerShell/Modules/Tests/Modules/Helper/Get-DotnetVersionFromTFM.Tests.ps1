#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Get-DotnetVersionFromTFM.ps1"
}

Describe "Get-DotnetVersionFromTFM" {
	Context "Modern .NET TFMs" {
		It "Should parse net8.0 correctly" {
			$result = Get-DotnetVersionFromTFM -TFM "net8.0"

			$result.Major | Should -Be 8
			$result.Minor | Should -Be 0
			$result.Version | Should -Be "8.0"
			$result.IsModern | Should -Be $true
			$result.IsFramework | Should -Be $false
		}

		It "Should parse net9.0 correctly" {
			$result = Get-DotnetVersionFromTFM -TFM "net9.0"

			$result.Major | Should -Be 9
			$result.Minor | Should -Be 0
			$result.Version | Should -Be "9.0"
			$result.IsModern | Should -Be $true
		}

		It "Should parse net6.0 correctly" {
			$result = Get-DotnetVersionFromTFM -TFM "net6.0"

			$result.Major | Should -Be 6
			$result.Minor | Should -Be 0
			$result.Version | Should -Be "6.0"
			$result.IsModern | Should -Be $true
		}

		It "Should parse net10.0 correctly" {
			$result = Get-DotnetVersionFromTFM -TFM "net10.0"

			$result.Major | Should -Be 10
			$result.Minor | Should -Be 0
			$result.Version | Should -Be "10.0"
			$result.IsModern | Should -Be $true
		}
	}

	Context ".NET Core TFMs" {
		It "Should parse netcoreapp3.1 correctly" {
			$result = Get-DotnetVersionFromTFM -TFM "netcoreapp3.1"

			$result.Major | Should -Be 3
			$result.Minor | Should -Be 1
			$result.Version | Should -Be "3.1"
			$result.IsModern | Should -Be $true
			$result.IsFramework | Should -Be $false
		}

		It "Should parse netcoreapp2.1 correctly" {
			$result = Get-DotnetVersionFromTFM -TFM "netcoreapp2.1"

			$result.Major | Should -Be 2
			$result.Minor | Should -Be 1
			$result.IsModern | Should -Be $true
		}
	}

	Context ".NET Framework TFMs" {
		It "Should identify net48 as Framework" {
			$result = Get-DotnetVersionFromTFM -TFM "net48"

			$result.IsFramework | Should -Be $true
			$result.IsModern | Should -Be $false
			$result.Version | Should -Be "Framework"
		}

		It "Should identify net472 as Framework" {
			$result = Get-DotnetVersionFromTFM -TFM "net472"

			$result.IsFramework | Should -Be $true
			$result.IsModern | Should -Be $false
		}

		It "Should identify net461 as Framework" {
			$result = Get-DotnetVersionFromTFM -TFM "net461"

			$result.IsFramework | Should -Be $true
		}
	}

	Context ".NET Standard TFMs" {
		It "Should identify netstandard2.0" {
			$result = Get-DotnetVersionFromTFM -TFM "netstandard2.0"

			$result.Version | Should -Be "Standard"
			$result.IsModern | Should -Be $false
			$result.IsFramework | Should -Be $false
		}

		It "Should identify netstandard2.1" {
			$result = Get-DotnetVersionFromTFM -TFM "netstandard2.1"

			$result.Version | Should -Be "Standard"
		}
	}

	Context "Invalid TFMs" {
		It "Should return null for unrecognized TFM" {
			$result = Get-DotnetVersionFromTFM -TFM "invalid"

			$result | Should -BeNullOrEmpty
		}

		It "Should throw on empty string (TFM is mandatory)" {
			{ Get-DotnetVersionFromTFM -TFM "" } | Should -Throw
		}
	}
}
