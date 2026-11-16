#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Get-RepositoryHooksState.ps1"
	. "$ModuleRoot\Git\Functions\Sync-RepositoryHooks.ps1"

	# The state file lives under LOCALAPPDATA, so that points into TestDrive: the machine's own
	# record is never read or written.
	$script:SavedLocalAppData = $env:LOCALAPPDATA
	$env:LOCALAPPDATA = Join-Path $TestDrive "AppData\Local"
	$script:StateFile = Join-Path $env:LOCALAPPDATA "WinuX\repository-hooks.state"
	$script:RepoCounter = 0
}

AfterAll {
	$env:LOCALAPPDATA = $script:SavedLocalAppData
}

# Real git: the value of these tests is what lands in (and stays out of) a clone's configuration.
Describe "Sync-RepositoryHooks" -Tag 'Integration' {
	BeforeEach {
		Mock Write-LogWarning { }
		Mock Write-LogSuccess { }
		Mock Write-LogError { }

		if (Test-Path -LiteralPath $script:StateFile) { Remove-Item -LiteralPath $script:StateFile -Force }

		# A fresh repository per test, with a tracked-style hooks folder.
		$script:RepoCounter++
		$script:Repo = Join-Path $TestDrive "repo$($script:RepoCounter)"
		New-Item -ItemType Directory -Path (Join-Path $script:Repo ".githooks") -Force | Out-Null
		git init --quiet $script:Repo 2>$null | Out-Null
	}

	Context "a repository marked with Hooks" {
		It "writes core.hooksPath into the clone's local configuration and records it" {
			$result = Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".githooks"

			$result.Outcome | Should -Be "Set"
			$result.Found | Should -Be ".githooks"
			git -C $script:Repo config --local --get core.hooksPath | Should -Be ".githooks"
			(Get-RepositoryHooksState).Entries[$script:Repo] | Should -Be ".githooks"
		}

		It "writes nothing the second time" {
			Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".githooks" | Out-Null
			$written = (Get-Item -LiteralPath $script:StateFile).LastWriteTimeUtc
			$configWritten = (Get-Item -LiteralPath (Join-Path $script:Repo ".git\config")).LastWriteTimeUtc

			$result = Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".githooks"

			$result.Outcome | Should -Be "AlreadySet"
			(Get-Item -LiteralPath $script:StateFile).LastWriteTimeUtc | Should -Be $written
			(Get-Item -LiteralPath (Join-Path $script:Repo ".git\config")).LastWriteTimeUtc | Should -Be $configWritten
		}

		It "sets it again on a clone where it was unset by hand" {
			Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".githooks" | Out-Null
			git -C $script:Repo config --local --unset core.hooksPath

			$result = Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".githooks"

			$result.Outcome | Should -Be "Set"
			git -C $script:Repo config --local --get core.hooksPath | Should -Be ".githooks"
		}

		It "replaces another value with the configured folder" {
			New-Item -ItemType Directory -Path (Join-Path $script:Repo "other") -Force | Out-Null
			git -C $script:Repo config --local core.hooksPath "other"

			$result = Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".githooks"

			$result.Outcome | Should -Be "Set"
			git -C $script:Repo config --local --get core.hooksPath | Should -Be ".githooks"
		}

		It "accepts the folder written with a backslash or a trailing slash" {
			New-Item -ItemType Directory -Path (Join-Path $script:Repo "tools\hooks") -Force | Out-Null

			$result = Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath "tools\hooks\"

			$result.Outcome | Should -Be "Set"
			$result.HooksPath | Should -Be "tools/hooks"
			git -C $script:Repo config --local --get core.hooksPath | Should -Be "tools/hooks"
		}

		It "does not adopt a value set by hand to the configured folder" {
			git -C $script:Repo config --local core.hooksPath ".githooks"

			$result = Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".githooks"

			$result.Outcome | Should -Be "AlreadySet"
			(Get-RepositoryHooksState).Entries.Count | Should -Be 0
		}

		It "reports a missing folder, writes nothing and does not create it" {
			$result = Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".hooks-typo"

			$result.Outcome | Should -Be "MissingFolder"
			git -C $script:Repo config --local --get core.hooksPath | Should -BeNullOrEmpty
			Test-Path -LiteralPath (Join-Path $script:Repo ".hooks-typo") | Should -BeFalse
			Test-Path -LiteralPath $script:StateFile | Should -BeFalse
			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}

		It "refuses a folder outside the repository (<Folder>)" -ForEach @(
			@{ Folder = "..\elsewhere" }
			@{ Folder = "sub/../../elsewhere" }
			@{ Folder = "C:\elsewhere" }
			@{ Folder = "~/hooks" }
		) {
			$result = Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath $Folder

			$result.Outcome | Should -Be "Invalid"
			git -C $script:Repo config --local --get core.hooksPath | Should -BeNullOrEmpty
		}

		It "never writes the global or system configuration, and never touches .git\hooks" {
			$globalBefore = "$(git config --global --get core.hooksPath 2>$null)"
			$systemBefore = "$(git config --system --get core.hooksPath 2>$null)"
			$hooksBefore = @(Get-ChildItem -LiteralPath (Join-Path $script:Repo ".git\hooks") -Force -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name)|$($_.Length)" })

			Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".githooks" | Out-Null

			"$(git config --global --get core.hooksPath 2>$null)" | Should -Be $globalBefore
			"$(git config --system --get core.hooksPath 2>$null)" | Should -Be $systemBefore
			@(Get-ChildItem -LiteralPath (Join-Path $script:Repo ".git\hooks") -Force -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name)|$($_.Length)" }) | Should -Be $hooksBefore
		}

		It "logs nothing with -Quiet" {
			Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".githooks" -Quiet | Out-Null
			Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".hooks-typo" -Quiet | Out-Null

			Should -Invoke Write-LogSuccess -Times 0 -Exactly
			Should -Invoke Write-LogWarning -Times 0 -Exactly
		}
	}

	Context "a repository that is not marked" {
		It "leaves a repository with a hooks folder untouched, without running git" {
			Mock git { throw "git must not run for an unmarked repository with nothing recorded" }

			$result = Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo

			$result.Outcome | Should -Be "None"
			Should -Invoke git -Times 0 -Exactly
			Test-Path -LiteralPath $script:StateFile | Should -BeFalse
		}

		It "leaves a value set by hand alone when nothing was recorded" {
			git -C $script:Repo config --local core.hooksPath ".githooks"

			$result = Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ""

			$result.Outcome | Should -Be "None"
			git -C $script:Repo config --local --get core.hooksPath | Should -Be ".githooks"
		}

		It "takes back the value it wrote once the mark is removed" {
			Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".githooks" | Out-Null

			$result = Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo

			$result.Outcome | Should -Be "Removed"
			git -C $script:Repo config --local --get core.hooksPath | Should -BeNullOrEmpty
			(Get-RepositoryHooksState).Entries.Count | Should -Be 0
		}

		It "keeps a value changed by hand since, reports it once and forgets the record" {
			Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".githooks" | Out-Null
			git -C $script:Repo config --local core.hooksPath "my-own-hooks"

			$first = Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo
			$second = Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo

			$first.Outcome | Should -Be "Kept"
			$first.Found | Should -Be "my-own-hooks"
			$second.Outcome | Should -Be "None"
			git -C $script:Repo config --local --get core.hooksPath | Should -Be "my-own-hooks"
			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}

		It "forgets the record when the value is already gone" {
			Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".githooks" | Out-Null
			git -C $script:Repo config --local --unset core.hooksPath

			$result = Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo

			$result.Outcome | Should -Be "Removed"
			(Get-RepositoryHooksState).Entries.Count | Should -Be 0
		}

		It "takes back only its own clone's value, leaving another clone's hand-set value" {
			$other = Join-Path $TestDrive "other$($script:RepoCounter)"
			New-Item -ItemType Directory -Path (Join-Path $other ".githooks") -Force | Out-Null
			git init --quiet $other 2>$null | Out-Null
			git -C $other config --local core.hooksPath ".githooks"
			Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo -HooksPath ".githooks" | Out-Null

			Sync-RepositoryHooks -Name MyRepo -LocalPath $script:Repo | Out-Null
			$otherResult = Sync-RepositoryHooks -Name Other -LocalPath $other

			$otherResult.Outcome | Should -Be "None"
			git -C $other config --local --get core.hooksPath | Should -Be ".githooks"
		}
	}

	Context "a path that is not its own repository" {
		It "writes nothing into the repository that encloses a plain folder" {
			$inner = Join-Path $script:Repo "inner"
			New-Item -ItemType Directory -Path (Join-Path $inner ".githooks") -Force | Out-Null

			$result = Sync-RepositoryHooks -Name Inner -LocalPath $inner -HooksPath ".githooks"

			$result.Outcome | Should -Be "NotARepository"
			git -C $script:Repo config --local --get core.hooksPath | Should -BeNullOrEmpty
		}

		It "writes nothing for a folder outside any repository" {
			$plain = Join-Path $TestDrive "plain$($script:RepoCounter)"
			New-Item -ItemType Directory -Path (Join-Path $plain ".githooks") -Force | Out-Null

			$result = Sync-RepositoryHooks -Name Plain -LocalPath $plain -HooksPath ".githooks"

			$result.Outcome | Should -Be "NotARepository"
			Test-Path -LiteralPath $script:StateFile | Should -BeFalse
		}
	}
}
