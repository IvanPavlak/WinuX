#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\Git\Functions\Get-RepositoryHooksState.ps1"

	$script:SavedLocalAppData = $env:LOCALAPPDATA
	$env:LOCALAPPDATA = Join-Path $TestDrive "AppData\Local"
	$script:StateFile = Join-Path $env:LOCALAPPDATA "WinuX\repository-hooks.state"
}

AfterAll {
	$env:LOCALAPPDATA = $script:SavedLocalAppData
}

Describe "Get-RepositoryHooksState" {
	BeforeEach {
		# The folder goes too: one test asserts that reading never creates it.
		$stateFolder = Split-Path -Parent $script:StateFile
		if (Test-Path -LiteralPath $stateFolder) { Remove-Item -LiteralPath $stateFolder -Recurse -Force }
	}

	It "returns no entries and the file's path when the file does not exist" {
		$state = Get-RepositoryHooksState

		$state.Path | Should -Be $script:StateFile
		$state.Entries.Count | Should -Be 0
		Test-Path -LiteralPath $script:StateFile | Should -BeFalse
	}

	It "reads one entry per path<TAB>folder line" {
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:StateFile) -Force | Out-Null
		Set-Content -LiteralPath $script:StateFile -Value @("# comment", "C:\Dev\MyRepo`t.githooks", "C:\Dev\Other`ttools/hooks")

		$state = Get-RepositoryHooksState

		$state.Entries.Count | Should -Be 2
		$state.Entries["C:\Dev\MyRepo"] | Should -Be ".githooks"
		$state.Entries["C:\Dev\Other"] | Should -Be "tools/hooks"
	}

	It "finds a path whatever its case" {
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:StateFile) -Force | Out-Null
		Set-Content -LiteralPath $script:StateFile -Value "C:\Dev\MyRepo`t.githooks"

		(Get-RepositoryHooksState).Entries["c:\dev\myrepo"] | Should -Be ".githooks"
	}

	It "skips comments, blank lines and lines without both parts" {
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:StateFile) -Force | Out-Null
		Set-Content -LiteralPath $script:StateFile -Value @("# header", "", "no-tab-here", "C:\Dev\NoValue`t", "`t.githooks", "C:\Dev\MyRepo`t.githooks")

		$state = Get-RepositoryHooksState

		$state.Entries.Count | Should -Be 1
		$state.Entries["C:\Dev\MyRepo"] | Should -Be ".githooks"
	}

	It "does not write or create the file" {
		Get-RepositoryHooksState | Out-Null

		Test-Path -LiteralPath (Split-Path -Parent $script:StateFile) | Should -BeFalse
	}
}
