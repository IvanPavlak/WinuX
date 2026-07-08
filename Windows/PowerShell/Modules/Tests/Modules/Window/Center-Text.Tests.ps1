#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Center-Text" {
	Context "Basic Centering" {
		It "Should center text with even padding" {
			$result = Center-Text -Text "Hi" -Width 6

			$result | Should -Be "  Hi  "
			$result.Length | Should -Be 6
		}

		It "Should center text with odd padding favoring left" {
			$result = Center-Text -Text "Hi" -Width 7

			$result | Should -Be "  Hi   "
			$result.Length | Should -Be 7
		}
	}

	Context "Edge Cases" {
		It "Should truncate text longer than width" {
			$result = Center-Text -Text "VeryLongText" -Width 5

			$result | Should -Be "VeryL"
			$result.Length | Should -Be 5
		}

		It "Should return text unchanged when exactly matching width" {
			$result = Center-Text -Text "Hello" -Width 5

			$result | Should -Be "Hello"
		}
	}
}
