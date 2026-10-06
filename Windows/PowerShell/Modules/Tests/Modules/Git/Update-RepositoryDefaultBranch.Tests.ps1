#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Update-RepositoryDefaultBranch.ps1"
}

Describe "Update-RepositoryDefaultBranch" {
	BeforeEach {
		# One git stand-in answering each subcommand from script state, so every test states only
		# the repository condition it is about. $args[2] is the subcommand: "-C <path>" comes first.
		$script:ShowRefExit = 0
		$script:FetchExit = 0
		$script:RemoteRefExit = 0
		$script:AncestorExit = 0
		$script:BeforeSha = "1111111"
		$script:AfterSha = "2222222"
		$script:LocalShaReads = 0

		Mock git {
			switch ($args[2]) {
				"show-ref" { $global:LASTEXITCODE = $script:ShowRefExit }
				"fetch" { $global:LASTEXITCODE = $script:FetchExit }
				"merge-base" { $global:LASTEXITCODE = $script:AncestorExit }
				"rev-parse" {
					if (($args -join " ") -match "refs/remotes/") {
						$global:LASTEXITCODE = $script:RemoteRefExit
						return
					}
					$global:LASTEXITCODE = 0
					$script:LocalShaReads++
					if ($script:LocalShaReads -eq 1) { $script:BeforeSha } else { $script:AfterSha }
				}
				default { $global:LASTEXITCODE = 0 }
			}
		}
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }

		$script:Call = @{ DefaultBranch = "master"; CurrentBranch = "feature"; LocalPath = "C:\Repos\MyRepo" }
	}

	Context "nothing to do" {
		It "returns Current and runs no git command when the default branch is checked out" {
			Update-RepositoryDefaultBranch -DefaultBranch "master" -CurrentBranch "master" -LocalPath "C:\Repos\MyRepo" |
				Should -Be "Current"
			Should -Invoke git -Times 0 -Exactly
		}

		It "returns Missing and never fetches when no local branch has that name" {
			$script:ShowRefExit = 1

			Update-RepositoryDefaultBranch @script:Call | Should -Be "Missing"
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[2] -eq "fetch" }
		}
	}

	Context "fast-forward" {
		It "fetches the default branch into itself with a refspec that has no force prefix" {
			Update-RepositoryDefaultBranch @script:Call | Out-Null

			Should -Invoke git -Times 1 -Exactly -ParameterFilter {
				$args[0] -eq "-C" -and $args[1] -eq "C:\Repos\MyRepo" -and
				$args[2] -eq "fetch" -and $args -contains "origin" -and $args -contains "master:master"
			}
		}

		It "returns Updated when the branch moved" {
			Update-RepositoryDefaultBranch @script:Call | Should -Be "Updated"
		}

		It "returns UpToDate when the branch did not move" {
			$script:AfterSha = $script:BeforeSha

			Update-RepositoryDefaultBranch @script:Call | Should -Be "UpToDate"
		}

		It "never checks a branch out, stashes or pulls" {
			Update-RepositoryDefaultBranch @script:Call | Out-Null

			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[2] -in @("checkout", "switch", "stash", "pull", "merge") }
		}
	}

	Context "fetch refused or failed" {
		BeforeEach { $script:FetchExit = 1 }

		It "returns Diverged when the local branch is not an ancestor of origin's" {
			$script:AncestorExit = 1

			Update-RepositoryDefaultBranch @script:Call | Should -Be "Diverged"
		}

		It "returns Failed when the local branch is an ancestor, so the fetch failed for another reason" {
			$script:AncestorExit = 0

			Update-RepositoryDefaultBranch @script:Call | Should -Be "Failed"
		}

		It "returns Failed without an ancestry check when origin has no such branch" {
			$script:RemoteRefExit = 1

			Update-RepositoryDefaultBranch @script:Call | Should -Be "Failed"
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[2] -eq "merge-base" }
		}

		It "returns Failed when the ancestry check itself errors" {
			$script:AncestorExit = 128

			Update-RepositoryDefaultBranch @script:Call | Should -Be "Failed"
		}
	}

	Context "-Quiet" {
		It "passes --quiet to the fetch" {
			Update-RepositoryDefaultBranch @script:Call -Quiet | Out-Null

			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[2] -eq "fetch" -and $args -contains "--quiet" }
		}

		It "does not pass --quiet without the switch" {
			Update-RepositoryDefaultBranch @script:Call | Out-Null

			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[2] -eq "fetch" -and $args -contains "--quiet" }
		}

		It "logs nothing for any outcome" {
			$script:FetchExit = 1
			$script:AncestorExit = 1

			Update-RepositoryDefaultBranch @script:Call -Quiet | Out-Null

			Should -Invoke Write-LogStep -Times 0 -Exactly
			Should -Invoke Write-LogSuccess -Times 0 -Exactly
			Should -Invoke Write-LogWarning -Times 0 -Exactly
			Should -Invoke Write-LogError -Times 0 -Exactly
		}

		It "still returns the outcome" {
			Update-RepositoryDefaultBranch @script:Call -Quiet | Should -Be "Updated"
		}
	}
}
