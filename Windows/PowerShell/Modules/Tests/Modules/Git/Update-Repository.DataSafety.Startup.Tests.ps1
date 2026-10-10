#Requires -Modules Pester

<#
	Data-safety integration tests, part "Startup": the startup update and Initialize-Repository lose nothing.

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

Describe "Repository update data safety (real git): the startup update and Initialize-Repository lose nothing" -Tag 'Integration' {
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

	Context "the startup update and Initialize-Repository" {
		It "S34 the startup update keeps staged and untracked work and releases its lock" {
			$dir = New-TestOrigin S34; $repo = New-TestClone $dir
			Set-Content "$repo\b.txt" "MINE"; Set-Content "$repo\u.txt" "u"; Set-Content "$repo\a.txt" "STAGED"; git -C $repo add a.txt
			Push-TestUpstream $dir master { Set-Content up.txt "x" }
			$global:LoggingState.LogsDir = "$dir\logs"
			Mock Resolve-RepositoryTargets { , @([pscustomobject]@{ Name = 'work'; Group = 'G'; RepositoryUrl = 'https://example.com/acme/work.git'; LocalPath = $repo }) }
			$before = Get-RepoFingerprint $repo

			Invoke-StartupRepositoryUpdate -Force
			$after = Get-RepoFingerprint $repo

			Get-LossViolations -Repo $repo -Before $before -After $after -Outcome 'n/a' -AnyOutcome | Should -BeNullOrEmpty
			"$repo\up.txt" | Should -Exist
			$after.Index['a.txt'] | Should -Be $before.Index['a.txt']
			"$dir\logs\.repository-update.lock" | Should -Not -Exist
		}

		It "S35 Initialize-Repository on an existing repository never overwrites an ignored file" {
			$dir = New-TestOrigin S35; $repo = New-TestClone $dir
			Set-Content "$repo\local.json" "MY SETTINGS"; Set-Content "$repo\b.txt" "MINE"
			Push-TestUpstream $dir master { Set-Content .gitignore "# none"; Set-Content local.json "UP" }
			$before = Get-RepoFingerprint $repo

			Initialize-Repository -RepositoryUrl 'https://example.com/acme/work.git' -LocalPath $repo

			Get-LossViolations -Repo $repo -Before $before -After (Get-RepoFingerprint $repo) -Outcome 'n/a' -AnyOutcome | Should -BeNullOrEmpty
			Get-Content "$repo\local.json" -Raw | Should -Match 'MY SETTINGS'
		}

		It "S36 Initialize-Repository on an existing dirty repository updates it and keeps the work" {
			$dir = New-TestOrigin S36; $repo = New-TestClone $dir
			Set-Content "$repo\b.txt" "MINE"; Set-Content "$repo\dir\c.txt" "STAGED"; git -C $repo add dir/c.txt; Set-Content "$repo\u.txt" "u"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-up`na3" }
			$before = Get-RepoFingerprint $repo

			Initialize-Repository -RepositoryUrl 'https://example.com/acme/work.git' -LocalPath $repo
			$after = Get-RepoFingerprint $repo

			Get-LossViolations -Repo $repo -Before $before -After $after -Outcome 'n/a' -AnyOutcome | Should -BeNullOrEmpty
			Get-Content "$repo\a.txt" -Raw | Should -Match 'a2-up'
			$after.Index['dir/c.txt'] | Should -Be $before.Index['dir/c.txt']
		}
	}
}
