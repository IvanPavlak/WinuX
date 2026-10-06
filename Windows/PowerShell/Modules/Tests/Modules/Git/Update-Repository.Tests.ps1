#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\Update-Repository.ps1"
	# Dot-sourced so they exist to Mock even in sessions whose imported Git module predates them.
	. "$FunctionsPath\Resolve-RepositoryDefaultBranch.ps1"
	. "$FunctionsPath\Update-RepositoryDefaultBranch.ps1"
}

Describe "Update-Repository" {
	BeforeEach {
		# One git stand-in answering from script state; every call is recorded in order so tests
		# can assert sequencing (the default branch before the stash pop, nothing after a failed
		# stash). The subcommand is matched on the joined arguments because the stash call is
		# prefixed with "-c user.name=... -c user.email=...".
		$script:Calls = [System.Collections.Generic.List[string]]::new()
		$script:Branch = "feature"
		$script:Status = ""
		$script:Behind = "0"
		$script:StashExit = 0
		$script:PullExit = 0
		$script:PopExit = 0
		$script:FetchExit = 0
		$script:UpstreamExit = 0

		Mock git {
			$line = $args -join " "
			$script:Calls.Add($line)
			$global:LASTEXITCODE = 0
			switch -Regex ($line) {
				"^rev-parse --abbrev-ref HEAD" { $script:Branch; break }
				"^rev-parse --verify --quiet refs/remotes/origin/" { $global:LASTEXITCODE = $script:UpstreamExit; break }
				"^fetch" { $global:LASTEXITCODE = $script:FetchExit; break }
				"^status --porcelain" { $script:Status; break }
				"stash push" { $global:LASTEXITCODE = $script:StashExit; break }
				"^rev-list" { $script:Behind; break }
				"^pull" { $global:LASTEXITCODE = $script:PullExit; break }
				"^stash pop" { $global:LASTEXITCODE = $script:PopExit; break }
			}
		}
		Mock Push-Location { }
		Mock Pop-Location { }
		Mock Resolve-RepositoryDefaultBranch { "master" }
		Mock Update-RepositoryDefaultBranch { $script:Calls.Add("default-branch"); "Updated" }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }

		$script:Call = @{ Name = "MyRepo"; LocalPath = "C:\Repos\MyRepo" }
	}

	Context "checked-out branch" {
		It "reports UpToDate and never pulls when origin has nothing new" {
			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "UpToDate"
			$result.Branch | Should -Be "feature"
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -eq "pull" }
		}

		It "fast-forwards only, from the checked-out branch, when behind" {
			$script:Behind = "3"

			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "Updated"
			Should -Invoke git -Times 1 -Exactly -ParameterFilter {
				$args[0] -eq "pull" -and $args -contains "origin" -and $args -contains "feature" -and $args -contains "--ff-only"
			}
		}

		It "works inside the repository and always leaves it again" {
			$result = Update-Repository @script:Call

			Should -Invoke Push-Location -Times 1 -Exactly -ParameterFilter { $Path -eq "C:\Repos\MyRepo" }
			Should -Invoke Pop-Location -Times 1 -Exactly
			$result.LocalPath | Should -Be "C:\Repos\MyRepo"
		}
	}

	Context "branch not on origin, or origin unreachable" {
		BeforeEach { $script:Status = " M file.txt" }

		It "reports NoUpstream and never pulls when origin does not have the branch" {
			$script:FetchExit = 128
			$script:UpstreamExit = 1

			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "NoUpstream"
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -in @("rev-list", "pull", "merge") }
		}

		It "reports FetchFailed instead of up to date when the fetch fails but origin has the branch" {
			$script:FetchExit = 128

			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "FetchFailed"
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -in @("rev-list", "pull") }
		}

		It "still restores the stashed changes on both" {
			$script:FetchExit = 128
			Update-Repository @script:Call | Out-Null

			$script:UpstreamExit = 1
			Update-Repository @script:Call | Out-Null

			Should -Invoke git -Times 2 -Exactly -ParameterFilter { $args[0] -eq "stash" -and $args[1] -eq "pop" }
		}

		It "still fast-forwards the default branch for a branch that is not on origin" {
			$script:FetchExit = 128
			$script:UpstreamExit = 1

			$result = Update-Repository @script:Call -IncludeDefaultBranch

			$result.DefaultBranchOutcome | Should -Be "Updated"
		}
	}

	Context "local changes" {
		BeforeEach { $script:Status = " M file.txt" }

		It "stashes untracked files too, under a branch-and-timestamp name, and pops them back" {
			$script:Behind = "1"

			$result = Update-Repository @script:Call

			Should -Invoke git -Times 1 -Exactly -ParameterFilter {
				($args -join " ") -match "stash push --include-untracked .*-m feature_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$"
			}
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "stash" -and $args[1] -eq "pop" }
			$result.Outcome | Should -Be "Updated"
			$result.StashName | Should -BeNullOrEmpty -Because "a popped stash no longer exists"
		}

		It "stashes with a throwaway identity so a machine without one can still stash" {
			Update-Repository @script:Call | Out-Null

			Should -Invoke git -Times 1 -Exactly -ParameterFilter {
				$args[0] -eq "-c" -and $args -contains "user.name=WinuX" -and $args -contains "user.email=winux@localhost"
			}
		}

		It "does nothing else when the stash fails" {
			$script:StashExit = 1

			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "StashFailed"
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -in @("fetch", "pull") }
			Should -Invoke Update-RepositoryDefaultBranch -Times 0 -Exactly
			Should -Invoke Pop-Location -Times 1 -Exactly
		}

		It "aborts a pull that cannot fast-forward and gives the changes back once" {
			$script:Behind = "2"
			$script:PullExit = 1

			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "Conflict"
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "merge" -and $args[1] -eq "--abort" }
			Should -Invoke git -Times 1 -Exactly -ParameterFilter { $args[0] -eq "stash" -and $args[1] -eq "pop" }
			$result.StashName | Should -BeNullOrEmpty
		}

		It "keeps the stash name when the changes cannot be restored after a failed pull" {
			$script:Behind = "2"
			$script:PullExit = 1
			$script:PopExit = 1

			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "Conflict"
			$result.StashName | Should -Match "^feature_"
		}

		It "reports StashConflict and keeps the stash name when the final pop conflicts" {
			$script:Behind = "1"
			$script:PopExit = 1

			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "StashConflict"
			$result.StashName | Should -Match "^feature_"
		}
	}

	Context "default branch" {
		It "is left alone without -IncludeDefaultBranch" {
			$result = Update-Repository @script:Call

			Should -Invoke Resolve-RepositoryDefaultBranch -Times 0 -Exactly
			Should -Invoke Update-RepositoryDefaultBranch -Times 0 -Exactly
			$result.DefaultBranchOutcome | Should -BeNullOrEmpty
		}

		It "is fast-forwarded with the resolved name, the current branch and the repository path" {
			$result = Update-Repository @script:Call -IncludeDefaultBranch

			Should -Invoke Update-RepositoryDefaultBranch -Times 1 -Exactly -ParameterFilter {
				$DefaultBranch -eq "master" -and $CurrentBranch -eq "feature" -and $LocalPath -eq "C:\Repos\MyRepo"
			}
			$result.DefaultBranch | Should -Be "master"
			$result.DefaultBranchOutcome | Should -Be "Updated"
		}

		It "runs before the stash is popped" {
			$script:Status = " M file.txt"
			$script:Behind = "1"

			Update-Repository @script:Call -IncludeDefaultBranch | Out-Null

			$defaultIndex = $script:Calls.IndexOf("default-branch")
			$popIndex = $script:Calls.FindIndex([Predicate[string]] { param($c) $c -like "stash pop*" })
			$defaultIndex | Should -BeGreaterOrEqual 0
			$defaultIndex | Should -BeLessThan $popIndex
		}

		It "still runs when the pull could not fast-forward" {
			$script:Behind = "1"
			$script:PullExit = 1

			$result = Update-Repository @script:Call -IncludeDefaultBranch

			$result.Outcome | Should -Be "Conflict"
			Should -Invoke Update-RepositoryDefaultBranch -Times 1 -Exactly
		}

		It "reports Unresolved and fetches nothing when no default branch can be named" {
			Mock Resolve-RepositoryDefaultBranch { $null }
			Mock git { $script:Calls.Add(($args -join " ")); $global:LASTEXITCODE = 1 } -ParameterFilter { $args[0] -eq "remote" }

			$result = Update-Repository @script:Call -IncludeDefaultBranch

			$result.DefaultBranchOutcome | Should -Be "Unresolved"
			Should -Invoke Update-RepositoryDefaultBranch -Times 0 -Exactly
		}

		It "asks origin for its default branch once when nothing names it, then uses the answer" {
			$script:ResolveCalls = 0
			Mock Resolve-RepositoryDefaultBranch {
				$script:ResolveCalls++
				if ($script:ResolveCalls -eq 1) { $null } else { "main" }
			}

			$result = Update-Repository @script:Call -IncludeDefaultBranch

			Should -Invoke git -Times 1 -Exactly -ParameterFilter { ($args -join " ") -eq "remote set-head origin --auto" }
			$result.DefaultBranch | Should -Be "main"
			Should -Invoke Update-RepositoryDefaultBranch -Times 1 -Exactly -ParameterFilter { $DefaultBranch -eq "main" }
		}

		It "does not ask origin when the default branch is already known" {
			Update-Repository @script:Call -IncludeDefaultBranch | Out-Null

			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -eq "remote" }
		}

		It "does not resolve again when asking origin failed" {
			Mock Resolve-RepositoryDefaultBranch { $null }
			Mock git { $global:LASTEXITCODE = 2 } -ParameterFilter { $args[0] -eq "remote" }

			Update-Repository @script:Call -IncludeDefaultBranch | Out-Null

			Should -Invoke Resolve-RepositoryDefaultBranch -Times 1 -Exactly
		}
	}

	Context "-Quiet" {
		BeforeEach {
			$script:Status = " M file.txt"
			$script:Behind = "1"
		}

		It "passes --quiet to the stash, fetch, pull and pop" {
			Update-Repository @script:Call -Quiet | Out-Null

			foreach ($subcommand in @("stash push", "fetch", "pull", "stash pop")) {
				$script:Calls | Where-Object { $_ -match [regex]::Escape($subcommand) -and $_ -match "--quiet" } |
					Should -Not -BeNullOrEmpty -Because "[$subcommand] must run with --quiet"
			}
		}

		It "logs nothing on success" {
			Update-Repository @script:Call -Quiet | Out-Null

			Should -Invoke Write-LogStep -Times 0 -Exactly
			Should -Invoke Write-LogSuccess -Times 0 -Exactly
			Should -Invoke Write-LogWarning -Times 0 -Exactly
		}

		It "silences the default-branch step too" {
			Update-Repository @script:Call -Quiet -IncludeDefaultBranch | Out-Null

			Should -Invoke Update-RepositoryDefaultBranch -Times 1 -Exactly -ParameterFilter { $Quiet }
		}

		It "does not pass --quiet to the stash, fetch, pull or pop without the switch" {
			Update-Repository @script:Call | Out-Null

			# Only the commands -Quiet controls. The read-only `rev-parse --verify --quiet` probe for
			# origin/<branch> always uses --quiet: there it silences git's own "not found" message.
			$script:Calls | Where-Object { $_ -match "(stash push|^fetch|^pull|^stash pop)" -and $_ -match "--quiet" } |
				Should -BeNullOrEmpty
		}
	}

	Context "output" {
		It "returns exactly one result object, never git's own output" {
			Mock git {
				$global:LASTEXITCODE = 0
				if ($args[0] -eq "rev-parse") { "feature" }
				elseif ($args[0] -eq "rev-list") { "1" }
				else { "git chatter that must not reach the caller" }
			}

			$output = @(Update-Repository @script:Call)

			$output.Count | Should -Be 1
			$output[0].Name | Should -Be "MyRepo"
		}

		It "reports Error and still leaves the repository when something throws" {
			Mock git { throw "boom" }

			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "Error"
			Should -Invoke Pop-Location -Times 1 -Exactly
		}
	}
}
