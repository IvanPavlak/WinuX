#Requires -Modules Pester

<#
	Data-safety integration tests, part "Stash": only the update's own stash is ever restored, and nothing is lost when git cannot finish.

	Real git, throwaway repositories in TestDrive, and a fingerprint of every file, commit, stash
	and branch before and after each update - see RepositoryDataSafetyFixtures.ps1 for the rules
	every case enforces. The scenarios are split over Update-Repository.DataSafety.*.Tests.ps1 so
	the harness runs them on parallel workers; Run-Tests -TestName "Update-Repository.DataSafety"
	runs all of them.
#>

BeforeAll {
	. (Join-Path $PSScriptRoot "RepositoryDataSafetyFixtures.ps1")
}

AfterAll {
	Restore-RepositoryDataSafety
}

Describe "Repository update data safety (real git): only the update's own stash is ever restored, and nothing is lost when git cannot finish" {
	BeforeAll {
		# Inside the Describe so the template lands in this block's TestDrive and outlives every Context.
		Initialize-RepositoryDataSafety
	}

	BeforeEach {
		Set-RepositoryDataSafetyDefaults
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Test-AdminPrivileges { }
		Mock takeown { } -ErrorAction SilentlyContinue
	}

	Context "the update's own stash" {
		It "S17 does not apply the user's older stash when the change is nothing git can stash" {
			$dir = New-TestOrigin S17; $repo = New-TestClone $dir
			Set-Content "$repo\old.txt" "user old work"; git -C $repo add old.txt; git -C $repo stash push --quiet -m 'USER OLD STASH'
			git @script:Git -C $repo submodule add --quiet "$dir\origin.git" sub 2>$null | Out-Null; git -C $repo commit --quiet -m 'add sub'
			git -C "$repo\sub" commit --quiet --allow-empty -m 'new in sub'

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -BeIn @('Updated', 'UpToDate')
			"$repo\old.txt" | Should -Not -Exist -Because "the user's own stash must not be applied"
		}

		It "S18 restores its own stash and leaves the user's older stash in place" {
			$dir = New-TestOrigin S18; $repo = New-TestClone $dir
			Set-Content "$repo\old.txt" "user old work"; git -C $repo add old.txt; git -C $repo stash push --quiet -m 'USER OLD STASH'
			Set-Content "$repo\b.txt" "MINE"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Updated'
			"$repo\old.txt" | Should -Not -Exist
		}

		It "S28 restores its own stash when another command stashes in between, and leaves that stash alone" {
			$dir = New-TestOrigin S28; $repo = New-TestClone $dir
			Set-Content "$repo\b.txt" "MINE"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }
			# The default-branch lookup runs between the update's stash and its restore.
			$script:IntruderRepo = $repo
			Mock Resolve-RepositoryDefaultBranch {
				Set-Content "$($script:IntruderRepo)\intruder.txt" "INTRUDER"
				git -C $script:IntruderRepo stash push --quiet --include-untracked -m 'INTRUDER STASH' 2>$null | Out-Null
				'master'
			}

			$run = Invoke-CheckedUpdate $repo -ExpectedForeignStash 'INTRUDER STASH'

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Updated'
			Get-Content "$repo\b.txt" -Raw | Should -Match 'MINE'
			"$repo\intruder.txt" | Should -Not -Exist -Because "the other command's stash must not be applied"
			@(git -C $repo stash list --format=%gs) | Should -Contain 'On master: INTRUDER STASH'
		}
	}

	Context "locked files (Windows)" {
		It "S19 gives everything back when an untracked file is locked during the stash" -Skip:(-not $IsWindows) {
			$dir = New-TestOrigin S19; $repo = New-TestClone $dir
			Set-Content "$repo\b.txt" "MINE"; Set-Content "$repo\locked.txt" "LOCKED UNTRACKED"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }
			$lock = [System.IO.File]::Open("$repo\locked.txt", 'Open', 'Read', 'Read')
			try { $run = Invoke-CheckedUpdate $repo } finally { $lock.Dispose() }

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -BeIn @('StashFailed', 'Updated', 'StashConflict')
		}

		It "S20 gives everything back when a modified tracked file is locked during the stash" -Skip:(-not $IsWindows) {
			$dir = New-TestOrigin S20; $repo = New-TestClone $dir
			Set-Content "$repo\b.txt" "MINE b"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }
			$lock = [System.IO.File]::Open("$repo\b.txt", 'Open', 'Read', 'Read')
			try { $run = Invoke-CheckedUpdate $repo } finally { $lock.Dispose() }

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -BeIn @('StashFailed', 'Updated', 'StashConflict', 'Conflict')
		}

		It "S21 loses nothing when the file upstream changes is locked during the fast-forward" -Skip:(-not $IsWindows) {
			$dir = New-TestOrigin S21; $repo = New-TestClone $dir
			Set-Content "$repo\b.txt" "MINE b"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }
			$lock = [System.IO.File]::Open("$repo\a.txt", 'Open', 'Read', 'Read')
			try { $run = Invoke-CheckedUpdate $repo } finally { $lock.Dispose() }

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -BeIn @('Updated', 'Conflict', 'Error', 'StashConflict')
		}
	}

	Context "nothing to pull, or nowhere to pull from" {
		It "S22 keeps local work on a branch that was never pushed" {
			$dir = New-TestOrigin S22; $repo = New-TestClone $dir
			git -C $repo switch --quiet -c localonly; Set-Content "$repo\b.txt" "MINE"; Set-Content "$repo\u.txt" "new"

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'NoUpstream'
		}

		It "S23 keeps local work when origin is unreachable" {
			$dir = New-TestOrigin S23; $repo = New-TestClone $dir
			Set-Content "$repo\b.txt" "MINE"; git -C $repo remote set-url origin "$dir\gone.git"

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'FetchFailed'
		}
	}

	Context "the default branch" {
		It "S24 never rewinds a default branch that has unpushed commits" {
			$dir = New-TestOrigin S24; $repo = New-TestClone $dir
			Add-TestCommit $repo 'm.txt' 'master local' 'unpushed on master'; git -C $repo switch --quiet feature

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'UpToDate'
			$run.Result.DefaultBranchOutcome | Should -Be 'Diverged'
		}

		It "S25 never touches a default branch checked out, with changes, in another worktree" {
			$dir = New-TestOrigin S25; $repo = New-TestClone $dir
			git -C $repo switch --quiet feature
			git -C $repo worktree add --quiet "$dir\wt-master" master 2>$null; Set-Content "$dir\wt-master\b.txt" "WT MINE"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }
			$otherBefore = Get-RepoFingerprint "$dir\wt-master"

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -BeIn @('UpToDate', 'Updated')
			Get-LossViolations -Repo "$dir\wt-master" -Before $otherBefore -After (Get-RepoFingerprint "$dir\wt-master") -Outcome 'n/a' | Should -BeNullOrEmpty
		}
	}
}
