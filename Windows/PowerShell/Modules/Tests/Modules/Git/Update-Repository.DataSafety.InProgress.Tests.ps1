#Requires -Modules Pester

<#
	Data-safety integration tests, part "InProgress": work in progress is never touched.

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

Describe "Repository update data safety (real git): work in progress is never touched" -Tag 'Integration' {
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

	Context "an operation in progress or a detached HEAD" {
		It "S11 leaves a detached HEAD where it is" {
			$dir = New-TestOrigin S11; $repo = New-TestClone $dir
			git -C $repo checkout --quiet v1 2>$null; Set-Content "$repo\b.txt" "MINE"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Detached'
		}

		It "S12 leaves a merge with conflicts alone" {
			$dir = New-TestOrigin S12; $repo = New-TestClone $dir
			git -C $repo switch --quiet feature; Set-Content "$repo\a.txt" "a1`na2-FEATURE`na3"; git -C $repo commit --quiet -am feat
			git -C $repo switch --quiet master; Set-Content "$repo\a.txt" "a1`na2-MASTER`na3"; git -C $repo commit --quiet -am mast
			git -C $repo merge feature 2>$null | Out-Null

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Busy'
			"$repo\.git\MERGE_HEAD" | Should -Exist
		}

		It "S13 leaves a resolved but uncommitted merge, and its resolution, alone" {
			$dir = New-TestOrigin S13; $repo = New-TestClone $dir
			git -C $repo switch --quiet feature; Set-Content "$repo\a.txt" "a1`na2-FEATURE`na3"; git -C $repo commit --quiet -am feat
			git -C $repo switch --quiet master; Set-Content "$repo\a.txt" "a1`na2-MASTER`na3"; git -C $repo commit --quiet -am mast
			git -C $repo merge feature 2>$null | Out-Null
			Set-Content "$repo\a.txt" "a1`na2-RESOLVED BY HAND`na3"; git -C $repo add a.txt

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Busy'
			"$repo\.git\MERGE_HEAD" | Should -Exist
			Get-Content "$repo\a.txt" -Raw | Should -Match 'RESOLVED BY HAND'
		}

		It "S14 leaves a rebase stopped on a conflict alone" {
			$dir = New-TestOrigin S14; $repo = New-TestClone $dir
			Set-Content "$repo\a.txt" "a1`na2-LOCAL`na3"; git -C $repo commit --quiet -am local
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-UP`na3" }
			git -C $repo fetch --quiet; git -C $repo rebase origin/master 2>$null | Out-Null

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Busy'
			((Test-Path "$repo\.git\rebase-merge") -or (Test-Path "$repo\.git\rebase-apply")) | Should -BeTrue
		}

		It "S15 leaves a cherry-pick stopped on a conflict alone" {
			$dir = New-TestOrigin S15; $repo = New-TestClone $dir
			git -C $repo switch --quiet feature; Set-Content "$repo\a.txt" "a1`na2-FEATURE`na3"; git -C $repo commit --quiet -am feat
			$pick = git -C $repo rev-parse HEAD
			git -C $repo switch --quiet master; Set-Content "$repo\a.txt" "a1`na2-MASTER`na3"; git -C $repo commit --quiet -am mast
			git -C $repo cherry-pick $pick 2>$null | Out-Null

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Busy'
		}

		It "S16 leaves a bisect alone" {
			$dir = New-TestOrigin S16; $repo = New-TestClone $dir
			git -C $repo bisect start 2>$null | Out-Null; git -C $repo bisect bad 2>$null | Out-Null

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Busy'
		}

		It "S37 leaves a repository in a conflicted restore alone on the next run" {
			$dir = New-TestOrigin S37; $repo = New-TestClone $dir
			Set-Content "$repo\a.txt" "a1`na2-MINE`na3"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-THEIRS`na3" }
			(Invoke-CheckedUpdate $repo).Result.Outcome | Should -Be 'StashConflict'

			$second = Invoke-CheckedUpdate $repo

			$second.Violations | Should -BeNullOrEmpty
			$second.Result.Outcome | Should -Be 'Busy'
			($second.After.Stashes -join ',') | Should -Be ($second.Before.Stashes -join ',') -Because "the kept stash must still be there, unchanged"
		}
	}

	Context "a path that is not its own repository" {
		It "S26 never touches the enclosing repository of a folder that is not a repository itself" {
			$dir = New-TestOrigin S26; $parent = New-TestClone $dir 'parent'
			Set-Content "$parent\b.txt" "PARENT MINE"; New-Item -ItemType Directory "$parent\inner" -Force | Out-Null
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }

			$run = Invoke-CheckedUpdate $parent -LocalPath "$parent\inner"

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'NotARepository'
			$run.After.HeadRef | Should -Be $run.Before.HeadRef -Because "the enclosing repository must not be updated"
		}

		It "S27 never touches a plain folder that is not a repository" {
			$folder = Join-Path $TestDrive 'S27\plain'; New-Item -ItemType Directory $folder -Force | Out-Null; Set-Content "$folder\notes.txt" "precious"

			$run = Invoke-CheckedUpdate $folder

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'NotARepository'
		}
	}
}
