#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\GitBranchDeleteAndPrune.ps1"
}

Describe "GitBranchDeleteAndPrune" {
	BeforeEach {
		Mock git { }
	}

	Context "When deleting a branch" {
		It "Should force-delete the branch and prune remote" {
			GitBranchDeleteAndPrune -BranchName "feature/old-branch"

			Should -Invoke git -Times 2 -Exactly
			Should -Invoke git -ParameterFilter { $args[0] -eq "branch" -and $args[1] -eq "-D" -and $args[2] -eq "feature/old-branch" }
			Should -Invoke git -ParameterFilter { $args[0] -eq "remote" -and $args[1] -eq "prune" -and $args[2] -eq "origin" }
		}

		It "Should call both git branch -D and git remote prune in sequence" {
			$callOrder = @()
			Mock git {
				if ($args[0] -eq "branch") { $callOrder += "branch" }
				if ($args[0] -eq "remote") { $callOrder += "remote" }
			}

			GitBranchDeleteAndPrune -BranchName "bugfix/123"

			Should -Invoke git -Times 2 -Exactly
		}
	}
}
