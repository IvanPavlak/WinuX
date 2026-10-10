#Requires -Modules Pester

BeforeAll {
	# Clean module state without re-importing (and re-dot-sourcing) the whole module.
	. (Join-Path (Get-RepositoryPath).Modules "Tests\Modules\Support\Reset-WindowModuleState.ps1")
	Reset-WindowModuleState
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
