#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\GitBranchDeleteAndPrune.ps1"
	. "$ModuleRoot\Helper\Functions\Resolve-Selection.ps1"
}

Describe "GitBranchDeleteAndPrune" {
	BeforeEach {
		Mock git { $global:LASTEXITCODE = 0 }
	}

	Context "When no branch is named" {
		BeforeEach {
			Mock git {
				$global:LASTEXITCODE = 0
				if ($args[0] -eq "for-each-ref") { "refs/heads/master", "refs/heads/feature/a", "refs/heads/feature/b" }
				if ($args[0] -eq "symbolic-ref") { "refs/heads/master" }
			}
		}

		It "Should offer every local branch but the checked-out one, multi-select with Enter allowed" {
			Mock Resolve-Selection { }

			GitBranchDeleteAndPrune

			Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter {
				($OptionList -join ",") -eq "feature/a,feature/b" -and $AllowMultipleSelections -and $AllowEmptyPromptResponse
			}
		}

		It "Should delete nothing and not prune when the answer is empty" {
			Mock Resolve-Selection { $null }

			GitBranchDeleteAndPrune

			Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "branch" }
			Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "remote" }
		}

		It "Should delete every selected branch and prune once" {
			Mock Resolve-Selection { "feature/a", "feature/b" }

			GitBranchDeleteAndPrune

			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "branch" -and $args[1] -eq "-D" -and $args[2] -eq "feature/a" }
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "branch" -and $args[1] -eq "-D" -and $args[2] -eq "feature/b" }
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "remote" -and $args[1] -eq "prune" -and $args[2] -eq "origin" }
		}

		It "Should not show a menu when only the checked-out branch exists" {
			Mock git {
				$global:LASTEXITCODE = 0
				if ($args[0] -eq "for-each-ref") { "refs/heads/master" }
				if ($args[0] -eq "symbolic-ref") { "refs/heads/master" }
			}
			Mock Resolve-Selection { }
			Mock Write-Host { }

			GitBranchDeleteAndPrune

			Should -Invoke Resolve-Selection -Times 0
			Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "branch" }
		}
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
				$global:LASTEXITCODE = 0
				if ($args[0] -eq "branch") { $callOrder += "branch" }
				if ($args[0] -eq "remote") { $callOrder += "remote" }
			}

			GitBranchDeleteAndPrune -BranchName "bugfix/123"

			Should -Invoke git -Times 2 -Exactly
		}
	}
}
