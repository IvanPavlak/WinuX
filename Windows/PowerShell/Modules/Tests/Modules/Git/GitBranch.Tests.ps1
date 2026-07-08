#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\GitBranch.ps1"
}

Describe "GitBranch" {
	BeforeEach {
		Mock git { }
	}

	Context "When no branch name is provided" {
		It "Should list all branches with verbose info" {
			GitBranch

			Should -Invoke git -ParameterFilter { $args[0] -eq "branch" -and $args[1] -eq "-v" -and $args[2] -eq "-a" }
		}
	}

	Context "When a branch name is provided" {
		It "Should create a new branch with the given name" {
			GitBranch -BranchName "feature/new-feature"

			Should -Invoke git -ParameterFilter { $args[0] -eq "branch" -and $args[1] -eq "feature/new-feature" }
		}
	}
}
