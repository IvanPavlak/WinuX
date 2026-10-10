#Requires -Modules Pester

<#
	Data-safety integration tests, part "LocalWork": ordinary local work survives an update.

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

Describe "Repository update data safety (real git): ordinary local work survives an update" -Tag 'Integration' {
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

	Context "staged, unstaged, untracked and ignored work" {
		It "S01 fast-forwards a clean repository" {
			$dir = New-TestOrigin S01; $repo = New-TestClone $dir
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Updated'
		}

		It "S02 keeps a modified tracked file while fast-forwarding another" {
			$dir = New-TestOrigin S02; $repo = New-TestClone $dir
			Set-Content "$repo\b.txt" "MINE"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Updated'
			Get-Content "$repo\a.txt" -Raw | Should -Match 'a2-up'
		}

		It "S03 restores partially staged changes as staged" {
			$dir = New-TestOrigin S03; $repo = New-TestClone $dir
			Set-Content "$repo\b.txt" "STAGED"; git -C $repo add b.txt; Set-Content "$repo\b.txt" "STAGED then more"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Updated'
			$run.After.Index['b.txt'] | Should -Be $run.Before.Index['b.txt'] -Because "the staged version must be staged again"
		}

		It "S04 keeps untracked files and folders" {
			$dir = New-TestOrigin S04; $repo = New-TestClone $dir
			Set-Content "$repo\new.txt" "new"; New-Item -ItemType Directory "$repo\newdir\deep" -Force | Out-Null; Set-Content "$repo\newdir\deep\x.txt" "deep"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Updated'
		}

		It "S05 keeps ignored files and folders" {
			$dir = New-TestOrigin S05; $repo = New-TestClone $dir
			Set-Content "$repo\debug.log" "log"; New-Item -ItemType Directory "$repo\bin" -Force | Out-Null; Set-Content "$repo\bin\app.exe" "exe"; Set-Content "$repo\b.txt" "MINE"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }

			$run = Invoke-CheckedUpdate $repo

			$run.Violations | Should -BeNullOrEmpty
			$run.Result.Outcome | Should -Be 'Updated'
		}
	}
}
