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
		Mock Write-Host { }
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

		It "Should delete every selected branch with a plain -d and prune once" {
			Mock Resolve-Selection { "feature/a", "feature/b" }

			GitBranchDeleteAndPrune

			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "branch" -and $args[1] -ceq "-d" -and $args[2] -eq "feature/a" }
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "branch" -and $args[1] -ceq "-d" -and $args[2] -eq "feature/b" }
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "remote" -and $args[1] -eq "prune" -and $args[2] -eq "origin" }
		}

		It "Should not show a menu when only the checked-out branch exists" {
			Mock git {
				$global:LASTEXITCODE = 0
				if ($args[0] -eq "for-each-ref") { "refs/heads/master" }
				if ($args[0] -eq "symbolic-ref") { "refs/heads/master" }
			}
			Mock Resolve-Selection { }

			GitBranchDeleteAndPrune

			Should -Invoke Resolve-Selection -Times 0
			Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "branch" }
		}
	}

	Context "When deleting a branch" {
		It "Should delete the branch with a plain -d and prune remote" {
			GitBranchDeleteAndPrune -BranchName "feature/old-branch"

			Should -Invoke git -Times 2 -Exactly
			Should -Invoke git -ParameterFilter { $args[0] -eq "branch" -and $args[1] -ceq "-d" -and $args[2] -eq "feature/old-branch" }
			Should -Invoke git -ParameterFilter { $args[0] -eq "remote" -and $args[1] -eq "prune" -and $args[2] -eq "origin" }
		}

		It "Should take several names positionally and prune once" {
			GitBranchDeleteAndPrune "feature/a", "feature/b"

			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "branch" -and $args[1] -ceq "-d" -and $args[2] -eq "feature/a" }
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "branch" -and $args[1] -ceq "-d" -and $args[2] -eq "feature/b" }
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "remote" }
		}

		It "Should delete with -D and ask nothing when -Force is given" {
			Mock Resolve-Selection { }

			GitBranchDeleteAndPrune -BranchName "feature/old-branch" -Force

			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "branch" -and $args[1] -ceq "-D" -and $args[2] -eq "feature/old-branch" }
			Should -Invoke git -Times 0 -ParameterFilter { $args[1] -ceq "-d" }
			Should -Invoke Resolve-Selection -Times 0
		}
	}

	Context "When git refuses a plain delete" {
		BeforeEach {
			# feature/unmerged is refused by -d; everything else succeeds.
			Mock git {
				$global:LASTEXITCODE = if ($args[0] -eq "branch" -and $args[1] -ceq "-d" -and $args[2] -eq "feature/unmerged") { 1 } else { 0 }
			}
		}

		It "Should ask once, red with Enter meaning No, about the refused branches only" {
			Mock Resolve-Selection { "No" }

			GitBranchDeleteAndPrune "feature/merged", "feature/unmerged"

			Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter {
				$ConfirmationMessage -like "*feature/unmerged*" -and $ConfirmationMessage -notlike "*feature/merged*"
			}
		}

		It "Should force-delete only the refused branches on Yes and prune once" {
			Mock Resolve-Selection { "Yes" }

			GitBranchDeleteAndPrune "feature/merged", "feature/unmerged"

			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "branch" -and $args[1] -ceq "-D" -and $args[2] -eq "feature/unmerged" }
			Should -Invoke git -Times 0 -ParameterFilter { $args[1] -ceq "-D" -and $args[2] -eq "feature/merged" }
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "remote" }
		}

		It "Should keep the refused branch on No and still prune for the one deleted" {
			Mock Resolve-Selection { "No" }

			GitBranchDeleteAndPrune "feature/merged", "feature/unmerged"

			Should -Invoke git -Times 0 -ParameterFilter { $args[1] -ceq "-D" }
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "remote" }
		}

		It "Should not prune when nothing was deleted" {
			Mock Resolve-Selection { "No" }

			GitBranchDeleteAndPrune "feature/unmerged"

			Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "remote" }
		}
	}
}
