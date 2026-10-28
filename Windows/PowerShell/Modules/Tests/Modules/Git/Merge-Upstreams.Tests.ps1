#Requires -Modules Pester

<#
	Merge-Upstreams against real throwaway repositories in TestDrive: an upstream that ships a
	manifest, a fork cloned from it (origin is the upstream, so the remote is found by URL), and
	commits pushed to the upstream afterwards. Every case asserts the staged tree, not messages.
#>

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	foreach ($name in 'ConvertFrom-UpstreamManifest', 'Resolve-UpstreamPathClass', 'Resolve-UpstreamRemote', 'Merge-Upstreams') {
		. (Join-Path $ModuleRoot "Git\Functions\$name.ps1")
	}

	$script:SavedIdentity = @{}
	foreach ($variable in 'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL') {
		$script:SavedIdentity[$variable] = [Environment]::GetEnvironmentVariable($variable)
	}
	$env:GIT_AUTHOR_NAME = 'Test'; $env:GIT_COMMITTER_NAME = 'Test'
	$env:GIT_AUTHOR_EMAIL = 'test@example.com'; $env:GIT_COMMITTER_EMAIL = 'test@example.com'

	$script:Case = 0

	# Writes files (relative path -> content) into a repository and commits them.
	function Set-TestFiles {
		param([string]$Repo, [hashtable]$Files, [string]$Message = 'change')
		foreach ($path in $Files.Keys) {
			$full = Join-Path $Repo $path
			if ($null -eq $Files[$path]) { & git -C $Repo rm -q -- $path; continue }
			New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
			[IO.File]::WriteAllText($full, $Files[$path])
		}
		& git -C $Repo add -A
		& git -C $Repo commit -q -m $Message
	}

	# An upstream named winux whose manifest owns Windows/ and mirrors LICENSE, and a fork cloned
	# from it. -TwoUpstreams gives the fork a second manifest (foundation, owning Unix/).
	function New-TestPair {
		param([switch]$TwoUpstreams, [string]$Changelog = "# Changelog`n`n## [Unreleased]`n`n## [2.0.0] - 2026-10-28`n", [string]$License = 'MIT')
		$script:Case++
		$dir = Join-Path $TestDrive "case$script:Case"
		$upstream = (Join-Path $dir 'upstream') -replace '\\', '/'
		$fork = Join-Path $dir 'fork'
		New-Item -ItemType Directory -Path $upstream -Force | Out-Null
		& git -C $upstream init -q -b master
		Set-TestFiles $upstream @{
			'Windows/PowerShell/Upstream.conf' = "name winux`nurl $upstream`ntag-prefix winux`nchangelog Windows/CHANGELOG.md`nown Windows/`nmirror LICENSE`n"
			'Windows/a.txt'                    = 'a1'
			'Windows/CHANGELOG.md'             = $Changelog
			'README.md'                        = 'upstream readme'
			'LICENSE'                          = $License
		} 'initial'
		& git clone -q $upstream $fork 2>$null
		if ($TwoUpstreams) {
			Set-TestFiles $fork @{
				'Unix/config/upstream.conf' = "name foundation`nurl https://example.invalid/acme/Foundation.git`nown Unix/`nmirror LICENSE`n"
				'README.md'                 = 'fork readme'
			} 'second upstream'
		}
		[pscustomobject]@{ Upstream = $upstream; Fork = $fork }
	}

	function Get-TestFile {
		param([string]$Repo, [string]$Path)
		$full = Join-Path $Repo $Path
		if (Test-Path -LiteralPath $full) { [IO.File]::ReadAllText($full) } else { $null }
	}

	function Test-MergeInProgress {
		param([string]$Repo)
		& git -C $Repo rev-parse -q --verify MERGE_HEAD *> $null
		$LASTEXITCODE -eq 0
	}
}

AfterAll {
	foreach ($variable in $script:SavedIdentity.Keys) {
		[Environment]::SetEnvironmentVariable($variable, $script:SavedIdentity[$variable])
	}
}

Describe "Merge-Upstreams (real git)" -Tag 'Integration' {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogList { }
	}

	Context "a fork of two upstreams (root owned by the fork)" {
		It "takes own and mirror paths and puts the hallway and the other upstream's rooms back" {
			$pair = New-TestPair -TwoUpstreams
			Set-TestFiles $pair.Upstream @{ 'Windows/a.txt' = 'a2'; 'README.md' = 'upstream readme v2'; 'LICENSE' = 'MIT v2'; 'Unix/x.txt' = 'not winux' }

			$result = Merge-Upstreams winux -RepositoryRoot $pair.Fork -PassThru

			$result.Status | Should -Be 'Staged'
			$result.Remote | Should -Be 'origin' -Because "the remote is found by the manifest URL, whatever it is called"
			Get-TestFile $pair.Fork 'Windows/a.txt' | Should -Be 'a2'
			Get-TestFile $pair.Fork 'LICENSE' | Should -Be 'MIT v2'
			Get-TestFile $pair.Fork 'README.md' | Should -Be 'fork readme'
			Get-TestFile $pair.Fork 'Unix/x.txt' | Should -BeNullOrEmpty
			$result.Declined | Should -Contain 'README.md'
			$result.Declined | Should -Contain 'Unix/x.txt'
			Test-MergeInProgress $pair.Fork | Should -BeTrue -Because "the merge is left staged, never committed"
			(& git -C $pair.Fork diff --cached --name-only) | Should -Not -Contain 'README.md'
		}

		It "removes a declined path the fork never had and prunes its empty folder" {
			$pair = New-TestPair -TwoUpstreams
			Set-TestFiles $pair.Upstream @{ 'Hall/Deep/new.md' = 'new'; 'Windows/a.txt' = 'a2' }

			$result = Merge-Upstreams winux -RepositoryRoot $pair.Fork -PassThru

			$result.Status | Should -Be 'Staged'
			Join-Path $pair.Fork 'Hall' | Should -Not -Exist
			(& git -C $pair.Fork diff --cached --name-only) | Should -Be @('Windows/a.txt')
		}

		It "adopts a hallway path named by a take line" {
			$pair = New-TestPair -TwoUpstreams
			New-Item -ItemType Directory -Path (Join-Path $pair.Fork 'Git') -Force | Out-Null
			[IO.File]::WriteAllText((Join-Path $pair.Fork 'Git/upstreams.local.conf'), "take winux .github/ISSUE_TEMPLATE/`n")
			Set-TestFiles $pair.Upstream @{ '.github/ISSUE_TEMPLATE/bug.yml' = 'bug'; 'README.md' = 'v2' }

			$result = Merge-Upstreams winux -RepositoryRoot $pair.Fork -PassThru

			Get-TestFile $pair.Fork '.github/ISSUE_TEMPLATE/bug.yml' | Should -Be 'bug'
			Get-TestFile $pair.Fork 'README.md' | Should -Be 'fork readme'
			$result.Taken['take'] | Should -Contain '.github/ISSUE_TEMPLATE/bug.yml'
		}

		It "takes the hallway when root-owner names the merged upstream" {
			$pair = New-TestPair -TwoUpstreams
			New-Item -ItemType Directory -Path (Join-Path $pair.Fork 'Git') -Force | Out-Null
			[IO.File]::WriteAllText((Join-Path $pair.Fork 'Git/upstreams.local.conf'), "root-owner winux`n")
			# Root.md is a hallway file the fork never edited (README.md, which it did edit, would conflict).
			Set-TestFiles $pair.Upstream @{ 'Root.md' = 'upstream root file'; 'Unix/x.txt' = 'not winux' }

			Merge-Upstreams winux -RepositoryRoot $pair.Fork | Out-Null

			Get-TestFile $pair.Fork 'Root.md' | Should -Be 'upstream root file'
			Get-TestFile $pair.Fork 'Unix/x.txt' | Should -BeNullOrEmpty -Because "another upstream's rooms are never written by this one"
		}

		It "reads the merged upstream's manifest as the upstream has it now" {
			$pair = New-TestPair -TwoUpstreams
			Set-TestFiles $pair.Upstream @{
				'Windows/PowerShell/Upstream.conf' = "name winux`nurl $($pair.Upstream)`nchangelog Windows/CHANGELOG.md`nown Windows/`nown Extra/`nmirror LICENSE`n"
				'Extra/e.txt'                      = 'extra'
			}

			Merge-Upstreams winux -RepositoryRoot $pair.Fork | Out-Null

			Get-TestFile $pair.Fork 'Extra/e.txt' | Should -Be 'extra'
		}
	}

	Context "a fork of one upstream" {
		It "takes the hallway by default, since the only upstream owns the root" {
			$pair = New-TestPair
			Set-TestFiles $pair.Upstream @{ 'README.md' = 'upstream readme v2'; 'NEW.md' = 'new' }

			$result = Merge-Upstreams winux -RepositoryRoot $pair.Fork -PassThru

			$result.Status | Should -Be 'Staged'
			Get-TestFile $pair.Fork 'README.md' | Should -Be 'upstream readme v2'
			Get-TestFile $pair.Fork 'NEW.md' | Should -Be 'new'
			$result.Declined.Count | Should -Be 0
		}
	}

	Context "dry run" {
		It "merges nothing and lists exactly what the real run then stages and puts back" {
			$pair = New-TestPair -TwoUpstreams
			Set-TestFiles $pair.Upstream @{ 'Windows/a.txt' = 'a2'; 'README.md' = 'v2'; 'Hall/new.md' = 'new' }
			$head = (& git -C $pair.Fork rev-parse HEAD)

			$dry = Merge-Upstreams winux -RepositoryRoot $pair.Fork -DryRun -PassThru

			$dry.Status | Should -Be 'DryRun'
			(& git -C $pair.Fork rev-parse HEAD) | Should -Be $head
			Test-MergeInProgress $pair.Fork | Should -BeFalse
			Get-TestFile $pair.Fork 'Windows/a.txt' | Should -Be 'a1'
			$dry.Taken['own'] | Should -Be @('M Windows/a.txt')
			$dry.Declined | Should -Contain 'U README.md' -Because "the fork edited README.md too, so the merge conflicts there, and putting it back resolves it"
			$dry.Declined | Should -Contain 'A Hall/new.md'
			$dry.Conflicts.Count | Should -Be 0 -Because "a conflict in a declined path is resolved by putting it back"

			$real = Merge-Upstreams winux -RepositoryRoot $pair.Fork -PassThru

			$real.Status | Should -Be 'Staged'
			@(& git -C $pair.Fork diff --cached --name-only) | Should -Be @($dry.Taken['own'] | ForEach-Object { ($_ -split ' ', 2)[1] })
			@($real.Declined | Sort-Object) | Should -Be @($dry.Declined | ForEach-Object { ($_ -split ' ', 2)[1] } | Sort-Object)
		}

		It "lists nothing the branch already has, however much the upstream changed" {
			$pair = New-TestPair -TwoUpstreams
			Set-TestFiles $pair.Fork @{ 'Windows/a.txt' = 'a2'; 'README.md' = 'fork readme v2' }
			Set-TestFiles $pair.Upstream @{ 'Windows/a.txt' = 'a2'; 'README.md' = 'fork readme v2' }

			$dry = Merge-Upstreams winux -RepositoryRoot $pair.Fork -DryRun -PassThru

			@($dry.Taken.Values | ForEach-Object { $_ }).Count | Should -Be 0
			$dry.Declined.Count | Should -Be 0
		}

		It "predicts a conflict in a taken path without starting a merge" {
			$pair = New-TestPair
			Set-TestFiles $pair.Fork @{ 'Windows/a.txt' = 'fork side' }
			Set-TestFiles $pair.Upstream @{ 'Windows/a.txt' = 'upstream side' }

			$dry = Merge-Upstreams winux -RepositoryRoot $pair.Fork -DryRun -PassThru

			$dry.Status | Should -Be 'DryRun'
			$dry.Conflicts | Should -Be @('Windows/a.txt')
			Test-MergeInProgress $pair.Fork | Should -BeFalse
			(Merge-Upstreams winux -RepositoryRoot $pair.Fork -PassThru).Conflicts | Should -Be $dry.Conflicts
		}

		It "warns of a mirror file whose merged copy would differ from the upstream's" {
			$pair = New-TestPair -License "line 1`nline 2`nline 3`nline 4`n"
			Set-TestFiles $pair.Fork @{ 'LICENSE' = "line 1 mine`nline 2`nline 3`nline 4`n" }
			Set-TestFiles $pair.Upstream @{ 'LICENSE' = "line 1`nline 2`nline 3`nline 4 theirs`n"; 'Windows/a.txt' = 'a2' }

			(Merge-Upstreams winux -RepositoryRoot $pair.Fork -DryRun -PassThru).MirrorDrift | Should -Be @('LICENSE')
		}

		It "does not warn of a mirror file the merge simply takes" {
			$pair = New-TestPair
			Set-TestFiles $pair.Upstream @{ 'LICENSE' = 'MIT v2' }

			$dry = Merge-Upstreams winux -RepositoryRoot $pair.Fork -DryRun -PassThru

			$dry.Taken['mirror'] | Should -Be @('M LICENSE')
			$dry.MirrorDrift.Count | Should -Be 0
		}

		It "does not refuse a dirty working tree" {
			$pair = New-TestPair
			Set-TestFiles $pair.Upstream @{ 'Windows/a.txt' = 'a2' }
			[IO.File]::WriteAllText((Join-Path $pair.Fork 'README.md'), 'edited')

			(Merge-Upstreams winux -RepositoryRoot $pair.Fork -DryRun -PassThru).Status | Should -Be 'DryRun'
		}
	}
	Context "refusals and stops" {
		It "refuses modified tracked files and changes nothing" {
			$pair = New-TestPair
			Set-TestFiles $pair.Upstream @{ 'Windows/a.txt' = 'a2' }
			[IO.File]::WriteAllText((Join-Path $pair.Fork 'README.md'), 'edited')

			(Merge-Upstreams winux -RepositoryRoot $pair.Fork -PassThru).Status | Should -Be 'Refused'
			Test-MergeInProgress $pair.Fork | Should -BeFalse
			Get-TestFile $pair.Fork 'README.md' | Should -Be 'edited'
		}

		It "refuses to start while a merge is in progress" {
			$pair = New-TestPair
			Set-TestFiles $pair.Upstream @{ 'Windows/a.txt' = 'a2' }
			[IO.File]::WriteAllText((Join-Path $pair.Fork '.git/MERGE_HEAD'), (& git -C $pair.Fork rev-parse HEAD))

			(Merge-Upstreams winux -RepositoryRoot $pair.Fork -PassThru).Status | Should -Be 'Refused'
		}

		It "prints the remote to add and writes no git configuration when none fits" {
			$pair = New-TestPair
			& git -C $pair.Fork remote remove origin

			(Merge-Upstreams winux -RepositoryRoot $pair.Fork -PassThru).Status | Should -Be 'NeedsRemote'
			@(& git -C $pair.Fork remote).Count | Should -Be 0
			Should -Invoke Write-LogList -ParameterFilter { $Items -contains "git remote add winux $($pair.Upstream)" }
		}

		It "is up to date when the upstream branch is already merged" {
			$pair = New-TestPair

			(Merge-Upstreams winux -RepositoryRoot $pair.Fork -PassThru).Status | Should -Be 'UpToDate'
		}

		It "prints the bridge merge for a branch with no common history" {
			$pair = New-TestPair
			$stranger = Join-Path $TestDrive "stranger$script:Case"
			New-Item -ItemType Directory -Path $stranger -Force | Out-Null
			& git -C $stranger init -q -b master
			Set-TestFiles $stranger @{ 'Windows/PowerShell/Upstream.conf' = "name winux`nurl $($pair.Upstream)`nown Windows/`n" } 'unrelated'
			& git -C $stranger remote add winux $pair.Upstream

			(Merge-Upstreams winux -RepositoryRoot $stranger -PassThru).Status | Should -Be 'NeedsBridge'
			Test-MergeInProgress $stranger | Should -BeFalse
		}

		It "leaves a conflict in a taken path for the owner and keeps the merge in progress" {
			$pair = New-TestPair
			Set-TestFiles $pair.Fork @{ 'Windows/a.txt' = 'fork side' }
			Set-TestFiles $pair.Upstream @{ 'Windows/a.txt' = 'upstream side' }

			$result = Merge-Upstreams winux -RepositoryRoot $pair.Fork -PassThru

			$result.Status | Should -Be 'Conflicts'
			$result.Conflicts | Should -Be @('Windows/a.txt')
			Test-MergeInProgress $pair.Fork | Should -BeTrue
		}

		It "resolves a conflict in a declined path by putting the fork's version back" {
			$pair = New-TestPair -TwoUpstreams
			Set-TestFiles $pair.Upstream @{ 'README.md' = 'upstream side' }

			$result = Merge-Upstreams winux -RepositoryRoot $pair.Fork -PassThru

			$result.Status | Should -Be 'Staged'
			Get-TestFile $pair.Fork 'README.md' | Should -Be 'fork readme'
		}
	}

	Context "the suggested commit message" {
		It "names the newest released version of the upstream's changelog" {
			$pair = New-TestPair
			Set-TestFiles $pair.Upstream @{ 'Windows/a.txt' = 'a2' }

			(Merge-Upstreams winux -RepositoryRoot $pair.Fork -PassThru).CommitMessage | Should -Be 'Merge winux master: 2.0.0'
		}

		It "says unreleased changes when the changelog has no release yet" {
			$pair = New-TestPair -Changelog "# Changelog`n`n## [Unreleased]`n"
			Set-TestFiles $pair.Upstream @{ 'Windows/a.txt' = 'a2' }

			(Merge-Upstreams winux -RepositoryRoot $pair.Fork -PassThru).CommitMessage | Should -Be 'Merge winux master: unreleased changes'
		}
	}
}
