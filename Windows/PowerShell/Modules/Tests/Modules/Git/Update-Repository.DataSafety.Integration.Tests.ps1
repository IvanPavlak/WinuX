#Requires -Modules Pester

<#
	Data-safety integration tests, part "Integration": Update-Repositories, Initialize-Repository and the startup update lose nothing.

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

Describe "Repository update data safety (real git): Update-Repositories, Initialize-Repository and the startup update lose nothing" {
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

	Context "through the callers" {
		It "S31 loses nothing across five repositories in different states" {
			$dir = New-TestOrigin S31
			$dirty = New-TestClone $dir 'dirty'; Set-Content "$dirty\b.txt" "MINE"; Set-Content "$dirty\u.txt" "u"; Set-Content "$dirty\a.txt" "STAGED"; git -C $dirty add a.txt
			$overlap = New-TestClone $dir 'overlap'; Set-Content "$overlap\a.txt" "a1`na2-MINE`na3"
			$merging = New-TestClone $dir 'merging'
			git -C $merging switch --quiet feature; Set-Content "$merging\a.txt" "a1`na2-F`na3"; git -C $merging commit --quiet -am f
			git -C $merging switch --quiet master; Set-Content "$merging\a.txt" "a1`na2-M`na3"; git -C $merging commit --quiet -am m
			git -C $merging merge feature 2>$null | Out-Null
			$onFeature = New-TestClone $dir 'onfeature'; git -C $onFeature switch --quiet feature; Set-Content "$onFeature\f.txt" "FEAT MINE"
			$ignored = New-TestClone $dir 'ignored'; Set-Content "$ignored\local.json" "MY SETTINGS"
			Push-TestUpstream $dir master { Set-Content a.txt "a1`na2-UP`na3"; Set-Content .gitignore "# none"; Set-Content local.json "UP" }
			Push-TestUpstream $dir feature { Set-Content f2.txt "f-up" }
			$repos = @($dirty, $overlap, $merging, $onFeature, $ignored)
			Mock Resolve-RepositoryTargets { , @($repos | ForEach-Object { [pscustomobject]@{ Name = (Split-Path $_ -Leaf); Group = 'G'; RepositoryUrl = "https://example.com/acme/$(Split-Path $_ -Leaf).git"; LocalPath = $_ } }) }
			$before = @{}; foreach ($r in $repos) { $before[$r] = Get-RepoFingerprint $r }

			Update-Repositories -All -NoClone -Quiet

			foreach ($r in $repos) {
				Get-LossViolations -Repo $r -Before $before[$r] -After (Get-RepoFingerprint $r) -Outcome 'n/a' -AnyOutcome | Should -BeNullOrEmpty -Because "[$(Split-Path $r -Leaf)] must lose nothing"
			}
			"$merging\.git\MERGE_HEAD" | Should -Exist
			Get-Content "$ignored\local.json" -Raw | Should -Match 'MY SETTINGS'
		}

		It "S32 clones a missing repository and loses nothing in the others" {
			$dir = New-TestOrigin S32; $present = New-TestClone $dir 'present'; Set-Content "$present\b.txt" "MINE"
			# A plain local path as the URL also proves a URL that yields no repository name does not stop the run.
			Mock Resolve-RepositoryTargets { , @(
					[pscustomobject]@{ Name = 'present'; Group = 'G'; RepositoryUrl = "$dir\origin.git"; LocalPath = $present }
					[pscustomobject]@{ Name = 'missing'; Group = 'G'; RepositoryUrl = "$dir\origin.git"; LocalPath = "$dir\missing" }
				) }
			$before = Get-RepoFingerprint $present

			Update-Repositories -All -Quiet

			Get-LossViolations -Repo $present -Before $before -After (Get-RepoFingerprint $present) -Outcome 'n/a' -AnyOutcome | Should -BeNullOrEmpty
			"$dir\missing\.git" | Should -Exist
		}

		It "S33 archive mode leaves an existing folder of the same name alone" {
			$dir = New-TestOrigin S33
			$out = Join-Path $dir 'out'; New-Item -ItemType Directory "$out\origin" -Force | Out-Null; Set-Content "$out\origin\keep.txt" "PRECIOUS, NOT A CLONE"
			$url = "file:///" + ("$dir\origin.git" -replace '\\', '/')
			Mock Resolve-RepositoryTargets { , @([pscustomobject]@{ Name = 'origin'; Group = 'G'; RepositoryUrl = $url; LocalPath = "$dir\nowhere" }) }

			Push-Location $out
			try { Update-Repositories -All -Archive -InCurrentDirectory } finally { Pop-Location }

			Get-Content "$out\origin\keep.txt" -Raw | Should -Match 'PRECIOUS'
			@(Get-ChildItem -LiteralPath "$out\origin" -Force).Count | Should -Be 1 -Because "nothing may be written into the existing folder"
			@(Get-ChildItem -LiteralPath $out -Directory).Count | Should -Be 1
		}

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
