#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\BranchExists.ps1"
}

Describe "BranchExists" {
	Context "Branch Detection" {
		It "Should return true when branch exists" {
			Mock git { "  main" } -ParameterFilter { $args[0] -eq "branch" -and $args[1] -eq "--list" }

			$result = BranchExists -Branch "main"

			$result | Should -Be $true
		}

		It "Should return false when branch does not exist" {
			Mock git { } -ParameterFilter { $args[0] -eq "branch" -and $args[1] -eq "--list" }

			$result = BranchExists -Branch "nonexistent-branch"

			$result | Should -Be $false
		}
	}
}
