#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Get-AiArtifactRoster.ps1"

	function New-Item-In([string]$Relative, [string]$File = "SKILL.md") {
		$dir = Join-Path $script:Root $Relative
		New-Item -ItemType Directory -Path (Split-Path -Parent (Join-Path $dir $File)) -Force | Out-Null
		Set-Content -Path (Join-Path $dir $File) -Value "content"
	}
}

Describe "Get-AiArtifactRoster" {
	BeforeEach {
		$script:Root = Join-Path $TestDrive "AI"
		if (Test-Path -Path $script:Root) { Remove-Item -Path $script:Root -Recurse -Force }
		$script:Config = @{ Root = $script:Root; Sources = @{ mattpocock = @{} }; Exclude = @() }
	}

	It "returns an empty roster for a missing root or kind folder" {
		$roster = Get-AiArtifactRoster -Kind Skills -Config $script:Config

		$roster.Items.Count | Should -Be 0
		$roster.Duplicates | Should -BeNullOrEmpty
		$roster.Kind | Should -Be "skills"
	}

	It "reads own first, then winux, example and configured sources in name order, and no other folder" {
		New-Item-In "Skills\winux\configurator"
		New-Item-In "Skills\mattpocock\tdd"
		New-Item-In "Skills\own\teach-me"
		New-Item-In "Skills\example\sample"
		New-Item-In "Skills\foundation\document"

		$roster = Get-AiArtifactRoster -Kind Skills -Config $script:Config

		@($roster.Items.Keys) | Should -Be @("teach-me", "sample", "tdd", "configurator")
		@($roster.Items.Values | ForEach-Object { $_.Source }) | Should -Be @("own", "example", "mattpocock", "winux")
		$roster.Items['tdd'].Path | Should -Be (Join-Path $script:Root "Skills\mattpocock\tdd")
	}

	It "lets own win an item name another source carries, and records the loser" {
		New-Item-In "Skills\winux\document"
		New-Item-In "Skills\own\Document"

		$roster = Get-AiArtifactRoster -Kind Skills -Config $script:Config

		$roster.Items.Count | Should -Be 1
		$roster.Items['document'].Source | Should -Be "own"
		$roster.Duplicates.Count | Should -Be 1
		$roster.Duplicates[0].Source | Should -Be "winux"
		$roster.Duplicates[0].KeptFrom | Should -Be "own"
	}

	It "recognises an item by its kind: SKILL.md, plugin.json, or any file that is not hidden" {
		New-Item-In "Skills\own\real"
		New-Item -ItemType Directory -Path (Join-Path $script:Root "Skills\own\empty") -Force | Out-Null
		New-Item-In "Mods\own\band" ".claude-plugin\plugin.json"
		New-Item-In "Mods\own\no-manifest" "README.md"
		New-Item-In "Rules\own\CoreAiRules" "managed-settings.json"
		New-Item-In "Rules\own\hidden-only" ".keep"

		@((Get-AiArtifactRoster -Kind Skills -Config $script:Config).Items.Keys) | Should -Be @("real")
		@((Get-AiArtifactRoster -Kind Mods -Config $script:Config).Items.Keys) | Should -Be @("band")
		@((Get-AiArtifactRoster -Kind Rules -Config $script:Config).Items.Keys) | Should -Be @("CoreAiRules")
	}

	It "drops an item excluded for every source or for one source" {
		New-Item-In "Rules\example\CoreAiRules" "RULES.md"
		New-Item-In "Rules\own\CoreAiRules" "RULES.md"
		New-Item-In "Rules\own\Other" "RULES.md"
		New-Item-In "Skills\mattpocock\tdd"
		$script:Config.Exclude = @("rules/example/coreairules", "skills/tdd")

		$rules = Get-AiArtifactRoster -Kind Rules -Config $script:Config

		@($rules.Items.Keys) | Should -Be @("CoreAiRules", "Other")
		$rules.Duplicates | Should -BeNullOrEmpty -Because "the excluded example is never a contender"
		(Get-AiArtifactRoster -Kind Skills -Config $script:Config).Items.Count | Should -Be 0
	}
}
