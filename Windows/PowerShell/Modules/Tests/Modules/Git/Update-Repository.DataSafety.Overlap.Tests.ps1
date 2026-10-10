#Requires -Modules Pester

<#
	Data-safety integration tests, part "Overlap": local work that overlaps or diverges from upstream survives an update.

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

Describe "Repository update data safety (real git): local work that overlaps or diverges from upstream survives an update" -Tag 'Integration' {
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

	Context "local edits that overlap upstream, and diverged or ahead branches" {
		It "S06 keeps the stash when a local edit overlaps an upstream edit" {
			$dir = New-TestOrigin S06; $repo = New-TestClone $dir
			Set-Content "$repo\a.txt" "a1`na2-MINE`na3"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-THEIRS`na3" }

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'StashConflict'
			$run.Result.StashName | Should -Not -BeNullOrEmpty
		}

		It "S07 keeps an untracked file where upstream adds the same path" {
			$dir = New-TestOrigin S07; $repo = New-TestClone $dir
			Set-Content "$repo\added.txt" "MY UNTRACKED"
			Push-TestUpstream $dir master { Set-Content added.txt "THEIRS" }

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -BeIn @('StashConflict', 'Updated')
		}

		It "S08 refuses to overwrite an ignored file that upstream starts tracking" {
			$dir = New-TestOrigin S08; $repo = New-TestClone $dir
			Set-Content "$repo\local.json" "MY PRECIOUS SETTINGS"
			Push-TestUpstream $dir master { Set-Content .gitignore "# nothing ignored"; Set-Content local.json "UPSTREAM" }

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Conflict'
			Get-Content "$repo\local.json" -Raw | Should -Match 'MY PRECIOUS SETTINGS'
		}

		It "S09 keeps local commits and changes when the branch has diverged" {
			$dir = New-TestOrigin S09; $repo = New-TestClone $dir
			Add-TestCommit $repo 'lc.txt' 'local commit'; Set-Content "$repo\b.txt" "MINE"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Conflict'
		}

		It "S10 keeps unpushed commits when the branch is only ahead" {
			$dir = New-TestOrigin S10; $repo = New-TestClone $dir
			Add-TestCommit $repo 'lc.txt' 'local commit'

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'UpToDate'
		}
	}

	Context "normal (not -Quiet) mode is just as safe" {
		It "S29 keeps the stash when the restore conflicts" {
			$dir = New-TestOrigin S29; $repo = New-TestClone $dir
			Set-Content "$repo\a.txt" "a1`na2-MINE`na3"; Set-Content "$repo\u.txt" "u"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-THEIRS`na3" }

			$run = Invoke-CheckedUpdate $repo -Loud

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'StashConflict'
		}

		It "S30 restores staged, untracked and ignored work" {
			$dir = New-TestOrigin S30; $repo = New-TestClone $dir
			Set-Content "$repo\b.txt" "STAGED"; git -C $repo add b.txt; Set-Content "$repo\u.txt" "u"; Set-Content "$repo\x.log" "x"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }

			$run = Invoke-CheckedUpdate $repo -Loud

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Updated'
			$run.After.Index['b.txt'] | Should -Be $run.Before.Index['b.txt']
		}
	}
}
