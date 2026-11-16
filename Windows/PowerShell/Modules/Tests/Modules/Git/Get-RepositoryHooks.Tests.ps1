#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Get-RepositoryHooksState.ps1"
	. "$ModuleRoot\Git\Functions\Resolve-RepositoryTargets.ps1"
	. "$ModuleRoot\Git\Functions\Get-RepositoryHooks.ps1"

	$script:SavedLocalAppData = $env:LOCALAPPDATA
	$env:LOCALAPPDATA = Join-Path $TestDrive "AppData\Local"
	$script:StateFile = Join-Path $env:LOCALAPPDATA "WinuX\repository-hooks.state"
	$script:RepoCounter = 0
}

AfterAll {
	$env:LOCALAPPDATA = $script:SavedLocalAppData
}

# Real git: the rows are what the clones' own configuration says.
Describe "Get-RepositoryHooks" -Tag 'Integration' {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogWarning { }
		Mock Write-LogSuccess { }

		if (Test-Path -LiteralPath $script:StateFile) { Remove-Item -LiteralPath $script:StateFile -Force }

		$script:RepoCounter++
		$script:Root = Join-Path $TestDrive "run$($script:RepoCounter)"
		$script:Repo = Join-Path $script:Root "MyRepo"
		New-Item -ItemType Directory -Path (Join-Path $script:Repo ".githooks") -Force | Out-Null
		git init --quiet $script:Repo 2>$null | Out-Null

		$script:Targets = @([PSCustomObject]@{ Name = "MyRepo"; Group = "Alpha"; RepositoryUrl = "u"; LocalPath = $script:Repo; ArchiveFolder = $null; Hooks = ".githooks" })
		Mock Resolve-RepositoryTargets { , $script:Targets }
	}

	It "reports <State> for a marked repository" -ForEach @(
		@{ State = "NotSet"; Value = $null; Folder = ".githooks" }
		@{ State = "Active"; Value = ".githooks"; Folder = ".githooks" }
		@{ State = "Different"; Value = "my-own-hooks"; Folder = ".githooks" }
		@{ State = "MissingFolder"; Value = ".hooks-typo"; Folder = ".hooks-typo" }
	) {
		if ($Value) { git -C $script:Repo config --local core.hooksPath $Value }
		$script:Targets[0].Hooks = $Folder

		$rows = @(Get-RepositoryHooks -PassThru)

		$rows.Count | Should -Be 1
		$rows[0].Name | Should -Be "MyRepo"
		$rows[0].HooksPath | Should -Be $Folder
		$rows[0].Found | Should -Be $Value
		$rows[0].State | Should -Be $State
	}

	It "lists only repositories marked with Hooks" {
		$script:Targets += [PSCustomObject]@{ Name = "Plain"; Group = "Alpha"; RepositoryUrl = "u"; LocalPath = (Join-Path $script:Root "Plain"); ArchiveFolder = $null; Hooks = $null }

		$rows = @(Get-RepositoryHooks -PassThru)

		$rows.Name | Should -Be "MyRepo"
	}

	It "reports a marked repository that is not cloned, has no path here, or is not its own repository" {
		$inner = Join-Path $script:Repo "inner"
		New-Item -ItemType Directory -Path $inner -Force | Out-Null
		$script:Targets = @(
			[PSCustomObject]@{ Name = "Gone"; Group = "Alpha"; RepositoryUrl = "u"; LocalPath = (Join-Path $script:Root "Gone"); ArchiveFolder = $null; Hooks = ".githooks" }
			[PSCustomObject]@{ Name = "Elsewhere"; Group = "Alpha"; RepositoryUrl = "u"; LocalPath = $null; ArchiveFolder = $null; Hooks = ".githooks" }
			[PSCustomObject]@{ Name = "Inner"; Group = "Alpha"; RepositoryUrl = "u"; LocalPath = $inner; ArchiveFolder = $null; Hooks = ".githooks" }
		)

		$rows = @(Get-RepositoryHooks -PassThru)

		$rows.State -join "," | Should -Be "NotCloned,NotConfigured,NotARepository"
	}

	It "lists a recorded clone whose entry is no longer marked as Stale" {
		git -C $script:Repo config --local core.hooksPath ".githooks"
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:StateFile) -Force | Out-Null
		Set-Content -LiteralPath $script:StateFile -Value "$($script:Repo)`t.githooks"
		$script:Targets[0].Hooks = $null

		$rows = @(Get-RepositoryHooks -PassThru)

		$rows.Count | Should -Be 1
		$rows[0].State | Should -Be "Stale"
		$rows[0].LocalPath | Should -Be $script:Repo
		$rows[0].Found | Should -Be ".githooks"
		$rows[0].HooksPath | Should -BeNullOrEmpty
	}

	It "does not list a recorded clone twice while it is still marked" {
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:StateFile) -Force | Out-Null
		Set-Content -LiteralPath $script:StateFile -Value "$($script:Repo)`t.githooks"

		@(Get-RepositoryHooks -PassThru).Count | Should -Be 1
	}

	It "changes neither the clone's configuration nor the state file" {
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:StateFile) -Force | Out-Null
		Set-Content -LiteralPath $script:StateFile -Value "C:\Gone\Repo`t.githooks"
		$stateBefore = Get-Content -LiteralPath $script:StateFile -Raw
		$configBefore = Get-Content -LiteralPath (Join-Path $script:Repo ".git\config") -Raw

		Get-RepositoryHooks | Out-Null

		Get-Content -LiteralPath $script:StateFile -Raw | Should -Be $stateBefore
		Get-Content -LiteralPath (Join-Path $script:Repo ".git\config") -Raw | Should -Be $configBefore
	}

	It "sets only the first row off from the title with a blank line" {
		$script:Targets += [PSCustomObject]@{ Name = "Gone"; Group = "Alpha"; RepositoryUrl = "u"; LocalPath = (Join-Path $script:Root "Gone"); ArchiveFolder = $null; Hooks = ".githooks" }
		$script:Targets += [PSCustomObject]@{ Name = "Elsewhere"; Group = "Alpha"; RepositoryUrl = "u"; LocalPath = $null; ArchiveFolder = $null; Hooks = ".githooks" }

		Get-RepositoryHooks

		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match "^\[MyRepo\]" -and -not $NoLeadingNewline }
		Should -Invoke Write-LogWarning -Times 2 -Exactly -ParameterFilter { $Message -match "^\[(Gone|Elsewhere)\]" -and $NoLeadingNewline }
	}

	It "returns nothing without -PassThru, and says so when no repository is marked" {
		$script:Targets = @()

		$output = @(Get-RepositoryHooks)

		$output.Count | Should -Be 0
		Should -Invoke Write-LogStep -Times 1 -Exactly
	}
}
