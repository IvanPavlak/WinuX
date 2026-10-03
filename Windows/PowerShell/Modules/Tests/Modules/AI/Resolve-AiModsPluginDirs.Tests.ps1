#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Resolve-AiModsPluginDirs.ps1"

	$script:Harness = "C:\Users\You\.claude\mods"
}

Describe "Resolve-AiModsPluginDirs" {
	It "returns the deployed links when nothing is set yet" {
		$result = Resolve-AiModsPluginDirs -Existing "" -Deployed @("$script:Harness\alpha", "$script:Harness\bravo") -Harness $script:Harness -Separator ';'

		$result | Should -Be "$script:Harness\alpha;$script:Harness\bravo"
	}

	It "keeps entries added by hand, after the deployed links and in their original order" {
		$existing = "D:\Plugins\one;$script:Harness\alpha;E:\two"

		$result = Resolve-AiModsPluginDirs -Existing $existing -Deployed @("$script:Harness\alpha") -Harness $script:Harness -Separator ';'

		$result | Should -Be "$script:Harness\alpha;D:\Plugins\one;E:\two"
	}

	It "drops entries under the harness that no longer have a mod" {
		$existing = "$script:Harness\gone;D:\Plugins\one"

		$result = Resolve-AiModsPluginDirs -Existing $existing -Deployed @("$script:Harness\alpha") -Harness $script:Harness -Separator ';'

		$result | Should -Be "$script:Harness\alpha;D:\Plugins\one"
	}

	It "collapses duplicates and empty entries" {
		$existing = ";D:\Plugins\one;;D:\Plugins\one;"

		$result = Resolve-AiModsPluginDirs -Existing $existing -Deployed @("$script:Harness\alpha", "$script:Harness\alpha", "") -Harness $script:Harness -Separator ';'

		$result | Should -Be "$script:Harness\alpha;D:\Plugins\one"
	}

	It "compares Windows paths case-insensitively, both for the harness and for duplicates" {
		$existing = "C:\USERS\YOU\.CLAUDE\MODS\gone;d:\plugins\ONE"

		$result = Resolve-AiModsPluginDirs -Existing $existing -Deployed @("$script:Harness\alpha", "D:\Plugins\one") -Harness $script:Harness -Separator ';'

		$result | Should -Be "$script:Harness\alpha;D:\Plugins\one"
	}

	It "uses ':' and exact comparison for WSL and macOS paths" {
		$harness = "/home/you/.claude/mods"
		$existing = "/opt/plugins/x:/home/you/.claude/mods/gone:/HOME/YOU/.claude/mods/kept"

		$result = Resolve-AiModsPluginDirs -Existing $existing -Deployed @("$harness/alpha") -Harness $harness -Separator ':'

		$result | Should -Be "/home/you/.claude/mods/alpha:/opt/plugins/x:/HOME/YOU/.claude/mods/kept"
	}

	It "passes a ~-prefixed entry through verbatim" {
		$harness = "/home/you/.claude/mods"

		$result = Resolve-AiModsPluginDirs -Existing "~/my-plugins/thing" -Deployed @("$harness/alpha") -Harness $harness -Separator ':'

		$result | Should -Be "/home/you/.claude/mods/alpha:~/my-plugins/thing"
	}

	It "does not treat a sibling folder that only shares the harness prefix as under the harness" {
		$existing = "C:\Users\You\.claude\mods-extra\thing"

		$result = Resolve-AiModsPluginDirs -Existing $existing -Deployed @() -Harness $script:Harness -Separator ';'

		$result | Should -Be "C:\Users\You\.claude\mods-extra\thing"
	}

	It "returns an empty string when nothing is deployed and nothing else is set" {
		Resolve-AiModsPluginDirs -Existing "$script:Harness\gone" -Deployed @() -Harness $script:Harness -Separator ';' | Should -Be ""
	}
}
