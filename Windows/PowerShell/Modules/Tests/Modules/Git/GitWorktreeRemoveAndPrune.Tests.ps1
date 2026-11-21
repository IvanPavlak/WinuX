#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\GitWorktreeRemoveAndPrune.ps1"
	. "$FunctionsPath\GitBranchDeleteAndPrune.ps1"
	. "$ModuleRoot\Helper\Functions\Resolve-Selection.ps1"
}

Describe "GitWorktreeRemoveAndPrune" {
	BeforeEach {
		# The main worktree (where the shell is), two linked ones, a detached one and a locked one.
		$script:Porcelain = @(
			"worktree C:/Repo", "HEAD 1111111111111111111111111111111111111111", "branch refs/heads/master", ""
			"worktree C:/Repo-a", "HEAD 2222222222222222222222222222222222222222", "branch refs/heads/feature/a", ""
			"worktree C:/Repo-b", "HEAD 3333333333333333333333333333333333333333", "branch refs/heads/feature/b", ""
			"worktree C:/Repo-detached", "HEAD 4444444444444444444444444444444444444444", "detached", ""
			"worktree C:/Repo-locked", "HEAD 5555555555555555555555555555555555555555", "branch refs/heads/feature/locked", "locked on a USB drive", ""
		)
		$script:Top = "C:/Repo"
		Mock git {
			$global:LASTEXITCODE = 0
			if ($args[0] -eq "worktree" -and $args[1] -eq "list") { $script:Porcelain }
			if ($args[0] -eq "rev-parse") { $script:Top }
		}
		Mock Write-Host { }
		Mock GitBranchDeleteAndPrune { }
	}

	Context "Pruning" {
		It "Should prune stale worktree entries before listing them" {
			$script:calls = @()
			Mock git {
				$global:LASTEXITCODE = 0
				$script:calls += "$($args[0]) $($args[1])"
				if ($args[0] -eq "worktree" -and $args[1] -eq "list") { $script:Porcelain }
			}
			Mock Resolve-Selection { }

			GitWorktreeRemoveAndPrune

			$script:calls[0] | Should -Be "worktree prune"
			$script:calls[1] | Should -Be "worktree list"
		}
	}

	Context "When no worktree is named" {
		It "Should offer the linked worktrees but the main, current and locked ones, multi-select with Enter allowed" {
			Mock Resolve-Selection { }

			GitWorktreeRemoveAndPrune

			Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter {
				($OptionList -join "|") -eq "feature/a -> C:/Repo-a|feature/b -> C:/Repo-b|(detached 4444444) -> C:/Repo-detached" -and
				$AllowMultipleSelections -and $AllowEmptyPromptResponse
			}
		}

		It "Should leave out the worktree the shell is in" {
			$script:Top = "C:/Repo-a"
			Mock Resolve-Selection { }

			GitWorktreeRemoveAndPrune

			Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter {
				($OptionList -join "|") -eq "feature/b -> C:/Repo-b|(detached 4444444) -> C:/Repo-detached"
			}
		}

		It "Should remove nothing when the answer is empty" {
			Mock Resolve-Selection { $null }

			GitWorktreeRemoveAndPrune

			Should -Invoke git -Times 0 -ParameterFilter { $args[0] -eq "worktree" -and $args[1] -eq "remove" }
		}

		It "Should not show a menu when only the main worktree exists" {
			$script:Porcelain = @("worktree C:/Repo", "HEAD 1111111111111111111111111111111111111111", "branch refs/heads/master", "")
			Mock Resolve-Selection { }

			GitWorktreeRemoveAndPrune

			Should -Invoke Resolve-Selection -Times 0
			Should -Invoke git -Times 0 -ParameterFilter { $args[1] -eq "remove" }
		}

		It "Should remove every selected worktree" {
			Mock Resolve-Selection {
				if ($OptionList -contains "Force") { "No" } else { "feature/a -> C:/Repo-a", "(detached 4444444) -> C:/Repo-detached" }
			}

			GitWorktreeRemoveAndPrune

			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "worktree" -and $args[1] -eq "remove" -and $args[2] -eq "C:/Repo-a" }
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "worktree" -and $args[1] -eq "remove" -and $args[2] -eq "C:/Repo-detached" }
			Should -Invoke git -Times 0 -ParameterFilter { $args[1] -eq "remove" -and $args[2] -eq "C:/Repo-b" }
		}
	}

	Context "When worktrees are named" {
		BeforeEach {
			Mock Resolve-Selection { "No" }
		}

		It "Should resolve a branch name and a path, and remove both plainly" {
			GitWorktreeRemoveAndPrune "feature/a", "C:\Repo-b"

			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[1] -eq "remove" -and $args[2] -eq "C:/Repo-a" }
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[1] -eq "remove" -and $args[2] -eq "C:/Repo-b" }
			Should -Invoke git -Times 0 -ParameterFilter { $args -contains "--force" }
		}

		It "Should pass --force with -Force" {
			GitWorktreeRemoveAndPrune "feature/a" -Force

			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[1] -eq "remove" -and $args[2] -eq "--force" -and $args[3] -eq "C:/Repo-a" }
		}

		It "Should refuse the main, current, locked and unknown worktrees and still remove the rest" {
			$script:Top = "C:/Repo-b"

			GitWorktreeRemoveAndPrune "master", "feature/b", "feature/locked", "feature/nope", "feature/a"

			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[1] -eq "remove" }
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[1] -eq "remove" -and $args[2] -eq "C:/Repo-a" }
		}

		It "Should remove a worktree named twice only once" {
			GitWorktreeRemoveAndPrune "feature/a", "C:/Repo-a"

			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[1] -eq "remove" }
		}
	}

	Context "Offering the branches" {
		It "Should ask once, Enter meaning No, about the branches of the removed worktrees only" {
			Mock git {
				$global:LASTEXITCODE = if ($args[1] -eq "remove" -and $args[2] -eq "C:/Repo-b") { 1 } else { 0 }
				if ($args[0] -eq "worktree" -and $args[1] -eq "list") { $script:Porcelain }
				if ($args[0] -eq "rev-parse") { $script:Top }
			}
			Mock Resolve-Selection { "No" }

			GitWorktreeRemoveAndPrune "feature/a", "feature/b", "C:/Repo-detached"

			Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter {
				($OptionList -join ",") -eq "Yes,No,Force" -and $DefaultOptionIndex -eq 2 -and
				$PromptMessage -like "*feature/a*" -and $PromptMessage -notlike "*feature/b*"
			}
			Should -Invoke GitBranchDeleteAndPrune -Times 0
		}

		It "Should not ask when no removed worktree had a branch" {
			Mock Resolve-Selection { }

			GitWorktreeRemoveAndPrune "C:/Repo-detached"

			Should -Invoke Resolve-Selection -Times 0
		}

		It "Should hand the branches to GitBranchDeleteAndPrune on Yes" {
			Mock Resolve-Selection { "Yes" }

			GitWorktreeRemoveAndPrune "feature/a", "feature/b"

			Should -Invoke GitBranchDeleteAndPrune -Times 1 -Exactly -ParameterFilter {
				($BranchName -join ",") -eq "feature/a,feature/b" -and -not $Force
			}
		}

		It "Should hand the branches to GitBranchDeleteAndPrune -Force on Force" {
			Mock Resolve-Selection { "Force" }

			GitWorktreeRemoveAndPrune "feature/a"

			Should -Invoke GitBranchDeleteAndPrune -Times 1 -Exactly -ParameterFilter { ($BranchName -join ",") -eq "feature/a" -and $Force }
		}

		It "Should never force the branches because the worktrees were forced" {
			Mock Resolve-Selection { "Yes" }

			GitWorktreeRemoveAndPrune "feature/a" -Force

			Should -Invoke GitBranchDeleteAndPrune -Times 1 -Exactly -ParameterFilter { -not $Force }
		}
	}
}
