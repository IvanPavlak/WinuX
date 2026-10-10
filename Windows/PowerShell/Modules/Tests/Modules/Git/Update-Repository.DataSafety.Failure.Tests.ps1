#Requires -Modules Pester

<#
	Data-safety integration tests, part "Failure": nothing is lost when git cannot finish.

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

Describe "Repository update data safety (real git): nothing is lost when git cannot finish" -Tag 'Integration' {
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
}
