#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Git\Functions"

	. "$FunctionsPath\Update-Repository.ps1"
	# Dot-sourced so they exist to Mock even in sessions whose imported Git module predates them.
	. "$FunctionsPath\Resolve-RepositoryDefaultBranch.ps1"
	. "$FunctionsPath\Update-RepositoryDefaultBranch.ps1"
	. "$FunctionsPath\Restore-RepositoryStash.ps1"
	. "$FunctionsPath\Set-GitConsoleColor.ps1"
}

Describe "Update-Repository" {
	BeforeEach {
		# One git stand-in answering from script state; every call is recorded in order so tests
		# can assert sequencing. The subcommand is matched on the joined arguments because the
		# stash call is prefixed with "-c user.name=... -c user.email=...".
		$script:Calls = [System.Collections.Generic.List[string]]::new()
		$script:GitDir = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
		New-Item -ItemType Directory -Path $script:GitDir -Force | Out-Null
		$script:InsideWorkTree = "true"
		$script:Prefix = ""
		$script:Unmerged = ""
		$script:Branch = "feature"
		$script:Status = ""
		$script:Behind = "0"
		$script:StashExit = 0
		$script:StashRefs = @("", "")     # refs/stash before and after the push
		$script:StashRefReads = 0
		$script:MergeExit = 0
		$script:FetchExit = 0
		$script:UpstreamExit = 0

		Mock git {
			$line = $args -join " "
			$script:Calls.Add($line)
			$global:LASTEXITCODE = 0
			switch -Regex ($line) {
				"^rev-parse --is-inside-work-tree" { $script:InsideWorkTree; break }
				"^rev-parse --show-prefix" { $script:Prefix; break }
				"^rev-parse --absolute-git-dir" { $script:GitDir; break }
				"^ls-files --unmerged" { $script:Unmerged; break }
				"^rev-parse --abbrev-ref HEAD" { $script:Branch; break }
				"^rev-parse --verify --quiet refs/stash" { $value = $script:StashRefs[[Math]::Min($script:StashRefReads, 1)]; $script:StashRefReads++; $value; break }
				"^rev-parse --verify --quiet refs/remotes/origin/" { $global:LASTEXITCODE = $script:UpstreamExit; break }
				"^status --porcelain" { $script:Status; break }
				"stash push" { $global:LASTEXITCODE = $script:StashExit; break }
				"^fetch" { $global:LASTEXITCODE = $script:FetchExit; break }
				"^rev-list" { $script:Behind; break }
				"^merge" { $global:LASTEXITCODE = $script:MergeExit; break }
			}
		}
		Mock Push-Location { }
		Mock Pop-Location { }
		Mock Resolve-RepositoryDefaultBranch { "master" }
		Mock Update-RepositoryDefaultBranch { $script:Calls.Add("default-branch"); "Updated" }
		Mock Restore-RepositoryStash { $script:Calls.Add("restore $StashCommit"); "Restored" }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Set-GitConsoleColor { $false }

		$script:Call = @{ Name = "MyRepo"; LocalPath = "C:\Repos\MyRepo" }
	}

	Context "git colors" {
		It "keeps git's colors for a console run and turns them off again afterwards" {
			Mock Set-GitConsoleColor { $true }

			Update-Repository @script:Call | Out-Null

			Should -Invoke Set-GitConsoleColor -Times 1 -Exactly -ParameterFilter { -not $Off }
			Should -Invoke Set-GitConsoleColor -Times 1 -Exactly -ParameterFilter { $Off }
		}

		It "leaves the colors alone when it did not turn them on (a caller did, or the output is redirected)" {
			Update-Repository @script:Call | Out-Null

			Should -Invoke Set-GitConsoleColor -Times 0 -Exactly -ParameterFilter { $Off }
		}

		It "turns them off even when the update fails" {
			Mock Set-GitConsoleColor { $true }
			Mock git { throw "git crashed" }

			(Update-Repository @script:Call).Outcome | Should -Be "Error"
			Should -Invoke Set-GitConsoleColor -Times 1 -Exactly -ParameterFilter { $Off }
		}

		It "never colors a quiet run, whose git output is dropped" {
			Update-Repository @script:Call -Quiet | Out-Null

			Should -Invoke Set-GitConsoleColor -Times 0 -Exactly
		}
	}

	Context "checked-out branch" {
		It "reports UpToDate and never fast-forwards when origin has nothing new" {
			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "UpToDate"
			$result.Branch | Should -Be "feature"
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -eq "merge" }
		}

		It "fast-forwards with a merge that refuses to overwrite ignored files, never with git pull" {
			$script:Behind = "3"

			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "Updated"
			Should -Invoke git -Times 1 -Exactly -ParameterFilter {
				$args[0] -eq "merge" -and $args -contains "--ff-only" -and $args -contains "--no-overwrite-ignore" -and $args -contains "origin/feature"
			}
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -eq "pull" }
		}

		It "reports Conflict and never runs merge --abort when the fast-forward is refused" {
			$script:Behind = "2"
			$script:MergeExit = 1

			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "Conflict"
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args -contains "--abort" }
		}

		It "works inside the repository and always leaves it again" {
			Update-Repository @script:Call | Out-Null

			Should -Invoke Push-Location -Times 1 -Exactly -ParameterFilter { $Path -eq "C:\Repos\MyRepo" }
			Should -Invoke Pop-Location -Times 1 -Exactly
		}
	}

	Context "refusing to touch what is not safe" {
		It "reports NotARepository and runs nothing else when the path is a folder inside another repository" {
			$script:Prefix = "inner/"

			$result = Update-Repository @script:Call -IncludeDefaultBranch

			$result.Outcome | Should -Be "NotARepository"
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -in @("status", "stash", "fetch", "merge", "-c") }
			Should -Invoke Update-RepositoryDefaultBranch -Times 0 -Exactly
		}

		It "reports NotARepository when the path is not inside any repository" {
			$script:InsideWorkTree = ""

			(Update-Repository @script:Call).Outcome | Should -Be "NotARepository"
		}

		It "reports Busy and runs nothing else during <Marker>" -ForEach @(
			@{ Marker = "MERGE_HEAD" }, @{ Marker = "CHERRY_PICK_HEAD" }, @{ Marker = "REVERT_HEAD" },
			@{ Marker = "rebase-merge" }, @{ Marker = "rebase-apply" }, @{ Marker = "BISECT_LOG" }
		) {
			New-Item -ItemType File -Path (Join-Path $script:GitDir $Marker) -Force | Out-Null
			$script:Status = " M file.txt"

			$result = Update-Repository @script:Call -IncludeDefaultBranch

			$result.Outcome | Should -Be "Busy"
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { ($args -join " ") -match "stash|^fetch|^merge" }
			Should -Invoke Update-RepositoryDefaultBranch -Times 0 -Exactly
		}

		It "reports Busy when there are unresolved conflicts" {
			$script:Unmerged = "100644 abc 1`ta.txt"

			(Update-Repository @script:Call).Outcome | Should -Be "Busy"
		}

		It "reports Detached, never stashes and never moves HEAD on a detached HEAD" {
			$script:Branch = "HEAD"
			$script:Status = " M file.txt"

			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "Detached"
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { ($args -join " ") -match "stash|^fetch|^merge" }
		}
	}

	Context "branch not on origin, or origin unreachable" {
		BeforeEach {
			$script:Status = " M file.txt"
			$script:StashRefs = @("", "aaa111")
		}

		It "reports NoUpstream and never fast-forwards when origin does not have the branch" {
			$script:FetchExit = 128
			$script:UpstreamExit = 1

			(Update-Repository @script:Call).Outcome | Should -Be "NoUpstream"
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -in @("rev-list", "merge") }
		}

		It "reports FetchFailed instead of up to date when the fetch fails but origin has the branch" {
			$script:FetchExit = 128

			(Update-Repository @script:Call).Outcome | Should -Be "FetchFailed"
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -in @("rev-list", "merge") }
		}

		It "still restores the stashed changes" {
			$script:FetchExit = 128

			Update-Repository @script:Call | Out-Null

			Should -Invoke Restore-RepositoryStash -Times 1 -Exactly -ParameterFilter { $StashCommit -eq "aaa111" }
		}
	}

	Context "local changes" {
		BeforeEach {
			$script:Status = " M file.txt"
			$script:Behind = "1"
			$script:StashRefs = @("", "aaa111")
		}

		It "stashes untracked files too, under a branch-and-timestamp name, with a throwaway identity" {
			Update-Repository @script:Call | Out-Null

			Should -Invoke git -Times 1 -Exactly -ParameterFilter {
				$line = $args -join " "
				$line -match "stash push --include-untracked .*-m feature_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$" -and
				$args -contains "user.name=WinuX" -and $args -contains "user.email=winux@localhost"
			}
		}

		It "restores exactly the stash it created, by its commit, and never pops blindly" {
			$result = Update-Repository @script:Call

			Should -Invoke Restore-RepositoryStash -Times 1 -Exactly -ParameterFilter { $StashCommit -eq "aaa111" }
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { ($args -join " ") -match "stash pop" }
			$result.Outcome | Should -Be "Updated"
			$result.StashName | Should -BeNullOrEmpty -Because "a restored stash no longer exists"
		}

		It "keeps the user's own older stash out of it: no new stash means nothing to restore" {
			# A dirty status git cannot stash (a submodule's new commits): the push succeeds without
			# creating anything, so refs/stash still names the user's older stash.
			$script:StashRefs = @("userstash", "userstash")

			$result = Update-Repository @script:Call

			Should -Invoke Restore-RepositoryStash -Times 0 -Exactly
			$result.Outcome | Should -Be "Updated"
		}

		It "restores right away and reports StashFailed when the push fails after creating the stash" {
			$script:StashExit = 1

			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "StashFailed"
			Should -Invoke Restore-RepositoryStash -Times 1 -Exactly -ParameterFilter { $StashCommit -eq "aaa111" }
			Should -Invoke git -Times 0 -Exactly -ParameterFilter { $args[0] -in @("fetch", "merge") }
			$result.StashName | Should -BeNullOrEmpty
		}

		It "reports StashFailed without restoring anything when the failed push created nothing" {
			$script:StashExit = 1
			$script:StashRefs = @("", "")

			(Update-Repository @script:Call).Outcome | Should -Be "StashFailed"
			Should -Invoke Restore-RepositoryStash -Times 0 -Exactly
		}

		It "names the kept stash when a failed push could not be undone" {
			$script:StashExit = 1
			Mock Restore-RepositoryStash { "Conflict" }

			(Update-Repository @script:Call).StashName | Should -Match "^feature_"
		}

		It "still restores the stash after a refused fast-forward" {
			$script:MergeExit = 1

			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "Conflict"
			Should -Invoke Restore-RepositoryStash -Times 1 -Exactly
		}

		It "reports StashConflict and keeps the stash name when the restore conflicts" {
			Mock Restore-RepositoryStash { "Conflict" }

			$result = Update-Repository @script:Call

			$result.Outcome | Should -Be "StashConflict"
			$result.StashName | Should -Match "^feature_"
		}

		It "reports StashMissing when something else took the stash" {
			Mock Restore-RepositoryStash { "Missing" }

			(Update-Repository @script:Call).Outcome | Should -Be "StashMissing"
		}

		It "tries to give the stash back when something throws after it was made" {
			Mock Update-RepositoryDefaultBranch { throw "boom" }

			$result = Update-Repository @script:Call -IncludeDefaultBranch

			$result.Outcome | Should -Be "Error"
			Should -Invoke Restore-RepositoryStash -Times 1 -Exactly -ParameterFilter { $StashCommit -eq "aaa111" }
			Should -Invoke Pop-Location -Times 1 -Exactly
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
			$result.DefaultBranchOutcome | Should -Be "Updated"
		}

		It "runs before the stash is restored" {
			$script:Status = " M file.txt"
			$script:Behind = "1"
			$script:StashRefs = @("", "aaa111")

			Update-Repository @script:Call -IncludeDefaultBranch | Out-Null

			$defaultIndex = $script:Calls.IndexOf("default-branch")
			$restoreIndex = $script:Calls.IndexOf("restore aaa111")
			$defaultIndex | Should -BeGreaterOrEqual 0
			$defaultIndex | Should -BeLessThan $restoreIndex
		}

		It "still runs on a detached HEAD, where the checked-out branch is skipped" {
			$script:Branch = "HEAD"

			Update-Repository @script:Call -IncludeDefaultBranch | Out-Null

			Should -Invoke Update-RepositoryDefaultBranch -Times 1 -Exactly
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
		}

		It "reports Unresolved and fetches nothing when no default branch can be named" {
			Mock Resolve-RepositoryDefaultBranch { $null }
			Mock git { $global:LASTEXITCODE = 1 } -ParameterFilter { $args[0] -eq "remote" }

			$result = Update-Repository @script:Call -IncludeDefaultBranch

			$result.DefaultBranchOutcome | Should -Be "Unresolved"
			Should -Invoke Update-RepositoryDefaultBranch -Times 0 -Exactly
		}
	}

	Context "-Quiet" {
		BeforeEach {
			$script:Status = " M file.txt"
			$script:Behind = "1"
			$script:StashRefs = @("", "aaa111")
		}

		It "passes --quiet to the stash, fetch and fast-forward, and to the restore" {
			Update-Repository @script:Call -Quiet | Out-Null

			foreach ($subcommand in @("stash push", "^fetch", "^merge")) {
				$script:Calls | Where-Object { $_ -match $subcommand -and $_ -match "--quiet" } |
					Should -Not -BeNullOrEmpty -Because "[$subcommand] must run with --quiet"
			}
			Should -Invoke Restore-RepositoryStash -Times 1 -Exactly -ParameterFilter { $Quiet }
		}

		It "does not pass --quiet to the stash, fetch or fast-forward without the switch" {
			Update-Repository @script:Call | Out-Null

			$script:Calls | Where-Object { $_ -match "(stash push|^fetch|^merge)" -and $_ -match "--quiet" } | Should -BeNullOrEmpty
		}

		It "logs nothing on success" {
			Update-Repository @script:Call -Quiet | Out-Null

			Should -Invoke Write-LogStep -Times 0 -Exactly
			Should -Invoke Write-LogSuccess -Times 0 -Exactly
			Should -Invoke Write-LogWarning -Times 0 -Exactly
		}
	}

	Context "output" {
		It "returns exactly one result object, never git's own output" {
			Mock git {
				$global:LASTEXITCODE = 0
				$line = $args -join " "
				if ($line -match "^rev-parse --is-inside-work-tree") { "true" }
				elseif ($line -match "^rev-parse --show-prefix") { "" }
				elseif ($line -match "^rev-parse --absolute-git-dir") { $script:GitDir }
				elseif ($line -match "^rev-parse --abbrev-ref") { "feature" }
				elseif ($line -match "^rev-list") { "1" }
				elseif ($line -match "^(ls-files|status|rev-parse)") { "" }
				else { "git chatter that must not reach the caller" }
			}

			$output = @(Update-Repository @script:Call)

			$output.Count | Should -Be 1
			$output[0].Name | Should -Be "MyRepo"
		}
	}
}
