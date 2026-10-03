#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Get-AiModRoster.ps1"
}

Describe "Get-AiModRoster" {
	BeforeEach {
		$script:Root = Join-Path $TestDrive "Mods"
		if (Test-Path -Path $script:Root) { Remove-Item -Path $script:Root -Recurse -Force }

		function New-Mod([string]$Relative) {
			$dir = Join-Path $script:Root "$Relative\.claude-plugin"
			New-Item -ItemType Directory -Path $dir -Force | Out-Null
			Set-Content -Path (Join-Path $dir "plugin.json") -Value '{"name":"x"}'
		}
	}

	It "returns an empty roster when the root does not exist" {
		$roster = Get-AiModRoster -Root (Join-Path $TestDrive "nope")

		$roster.Mods.Count | Should -Be 0
		$roster.Duplicates | Should -BeNullOrEmpty
	}

	It "returns an empty roster when the root has no mods" {
		New-Item -ItemType Directory -Path (Join-Path $script:Root "own") -Force | Out-Null

		(Get-AiModRoster -Root $script:Root).Mods.Count | Should -Be 0
	}

	It "flattens every source into one map keyed by mod name" {
		New-Mod "neon\alpha"
		New-Mod "neon\bravo"
		New-Mod "own\charlie"

		$roster = Get-AiModRoster -Root $script:Root

		$roster.Mods.Count | Should -Be 3
		@($roster.Mods.Keys) | Should -Be @("alpha", "bravo", "charlie")
		$roster.Mods['charlie'].Source | Should -Be "own"
		$roster.Mods['alpha'].Path | Should -Be (Join-Path $script:Root "neon\alpha")
		$roster.Mods['alpha'].Name | Should -Be "alpha"
	}

	It "reports the root it walked" {
		New-Mod "own\alpha"

		(Get-AiModRoster -Root $script:Root).Root | Should -Be $script:Root
	}

	It "ignores a folder without .claude-plugin\plugin.json, including a plugin folder without the manifest" {
		New-Mod "own\alpha"
		New-Item -ItemType Directory -Path (Join-Path $script:Root "own\not-a-mod") -Force | Out-Null
		New-Item -ItemType Directory -Path (Join-Path $script:Root "own\half-a-mod\.claude-plugin") -Force | Out-Null

		@((Get-AiModRoster -Root $script:Root).Mods.Keys) | Should -Be @("alpha")
	}

	It "keeps the first source alphabetically when a mod name appears twice and records the loser" {
		New-Mod "aaa\shared"
		New-Mod "zzz\shared"

		$roster = Get-AiModRoster -Root $script:Root

		$roster.Mods.Count | Should -Be 1
		$roster.Mods['shared'].Source | Should -Be "aaa"
		$roster.Duplicates.Count | Should -Be 1
		$roster.Duplicates[0].Name | Should -Be "shared"
		$roster.Duplicates[0].Source | Should -Be "zzz"
		$roster.Duplicates[0].KeptFrom | Should -Be "aaa"
	}

	It "walks sources in name order so the roster is stable" {
		New-Mod "zzz\one"
		New-Mod "aaa\two"

		@((Get-AiModRoster -Root $script:Root).Mods.Keys) | Should -Be @("two", "one")
	}

	It "falls back to the configured root when none is given" {
		New-Mod "own\alpha"
		Mock Resolve-AiModsConfig { @{ Root = $script:Root; Harnesses = @(); WSLHarnesses = @(); Sources = @{} } }

		$roster = Get-AiModRoster

		$roster.Root | Should -Be $script:Root
		@($roster.Mods.Keys) | Should -Be @("alpha")
		Should -Invoke Resolve-AiModsConfig -Times 1 -Exactly
	}
}
