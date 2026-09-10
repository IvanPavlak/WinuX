#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Get-AiSkillRoster.ps1"
}

Describe "Get-AiSkillRoster" {
	BeforeEach {
		$script:Root = Join-Path $TestDrive "Skills"
		if (Test-Path -Path $script:Root) { Remove-Item -Path $script:Root -Recurse -Force }

		function New-Skill([string]$Relative) {
			$dir = Join-Path $script:Root $Relative
			New-Item -ItemType Directory -Path $dir -Force | Out-Null
			Set-Content -Path (Join-Path $dir "SKILL.md") -Value "skill"
		}
	}

	It "returns an empty roster when the root does not exist" {
		$roster = Get-AiSkillRoster -Root (Join-Path $TestDrive "nope")

		$roster.Skills.Count | Should -Be 0
		$roster.Duplicates | Should -BeNullOrEmpty
	}

	It "returns an empty roster when the root has no skills" {
		New-Item -ItemType Directory -Path (Join-Path $script:Root "mattpocock") -Force | Out-Null

		(Get-AiSkillRoster -Root $script:Root).Skills.Count | Should -Be 0
	}

	It "flattens every source into one map keyed by skill name" {
		New-Skill "mattpocock\alpha"
		New-Skill "mattpocock\bravo"
		New-Skill "own\charlie"

		$roster = Get-AiSkillRoster -Root $script:Root

		$roster.Skills.Count | Should -Be 3
		@($roster.Skills.Keys) | Should -Be @("alpha", "bravo", "charlie")
		$roster.Skills['charlie'].Source | Should -Be "own"
		$roster.Skills['alpha'].Path | Should -Be (Join-Path $script:Root "mattpocock\alpha")
		$roster.Skills['alpha'].Name | Should -Be "alpha"
	}

	It "reports the root it walked" {
		New-Skill "own\alpha"

		(Get-AiSkillRoster -Root $script:Root).Root | Should -Be $script:Root
	}

	It "ignores a folder without a SKILL.md" {
		New-Skill "own\alpha"
		New-Item -ItemType Directory -Path (Join-Path $script:Root "own\not-a-skill") -Force | Out-Null

		$roster = Get-AiSkillRoster -Root $script:Root

		@($roster.Skills.Keys) | Should -Be @("alpha")
	}

	It "keeps the first source alphabetically when a skill name appears twice and records the loser" {
		New-Skill "aaa\shared"
		New-Skill "zzz\shared"

		$roster = Get-AiSkillRoster -Root $script:Root

		$roster.Skills.Count | Should -Be 1
		$roster.Skills['shared'].Source | Should -Be "aaa"
		$roster.Duplicates.Count | Should -Be 1
		$roster.Duplicates[0].Name | Should -Be "shared"
		$roster.Duplicates[0].Source | Should -Be "zzz"
		$roster.Duplicates[0].KeptFrom | Should -Be "aaa"
	}

	It "walks sources in name order so the roster is stable" {
		New-Skill "zzz\one"
		New-Skill "aaa\two"

		@((Get-AiSkillRoster -Root $script:Root).Skills.Keys) | Should -Be @("two", "one")
	}

	It "falls back to the configured root when none is given" {
		New-Skill "own\alpha"
		Mock Resolve-AiSkillsConfig { @{ Root = $script:Root; Harnesses = @(); WSLHarnesses = @(); Sources = @{} } }

		$roster = Get-AiSkillRoster

		$roster.Root | Should -Be $script:Root
		@($roster.Skills.Keys) | Should -Be @("alpha")
		Should -Invoke Resolve-AiSkillsConfig -Times 1 -Exactly
	}
}
