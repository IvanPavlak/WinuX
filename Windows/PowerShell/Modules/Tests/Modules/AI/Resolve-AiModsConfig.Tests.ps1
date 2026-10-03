#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Resolve-AiModsConfig.ps1"
}

Describe "Resolve-AiModsConfig" {
	BeforeEach {
		Mock Get-RepositoryPath { @{ Repo = "C:\Repo" } }
	}

	It "falls back to the built-in defaults when the section is missing" {
		$result = Resolve-AiModsConfig -Configuration @{} -RepoRoot "C:\Repo"

		$result.Root | Should -Be "C:\Repo\AI\Mods"
		$result.Harnesses | Should -Be @("$env:USERPROFILE\.claude\mods")
		$result.WSLHarnesses | Should -BeNullOrEmpty
		$result.Sources.Count | Should -Be 0
	}

	It "expands {RepoRoot}, {User} and {AppData} in Root and Harnesses" {
		$config = @{
			AiMods = @{
				Root      = "{RepoRoot}\Elsewhere\Mods"
				Harnesses = @("{User}\.claude\mods", "{AppData}\tool\mods", "D:\literal\mods")
			}
		}

		$result = Resolve-AiModsConfig -Configuration $config -RepoRoot "C:\Repo"

		$result.Root | Should -Be "C:\Repo\Elsewhere\Mods"
		$result.Harnesses | Should -Be @("$env:USERPROFILE\.claude\mods", "$env:APPDATA\tool\mods", "D:\literal\mods")
	}

	It "derives the settings file from the user profile, not from configuration" {
		$config = @{ AiMods = @{ SettingsPath = "D:\ignored.json" } }

		$result = Resolve-AiModsConfig -Configuration $config -RepoRoot "C:\Repo"

		$result.SettingsPath | Should -Be (Join-Path $env:USERPROFILE ".claude\settings.json")
	}

	It "derives the WSL harnesses and WSL settings file from the {User} entries and DefaultWSLUsername" {
		$config = @{
			DefaultWSLUsername = "you"
			AiMods             = @{
				Harnesses = @("{User}\.claude\mods", "D:\literal\mods")
			}
		}

		$result = Resolve-AiModsConfig -Configuration $config -RepoRoot "C:\Repo"

		$result.WSLHarnesses | Should -Be @("/home/you/.claude/mods")
		$result.WSLSettingsPath | Should -Be "/home/you/.claude/settings.json"
	}

	It "yields no WSL harnesses and no WSL settings file when DefaultWSLUsername is empty" {
		$config = @{
			DefaultWSLUsername = ""
			AiMods             = @{ Harnesses = @("{User}\.claude\mods") }
		}

		$result = Resolve-AiModsConfig -Configuration $config -RepoRoot "C:\Repo"

		$result.WSLHarnesses | Should -BeNullOrEmpty
		$result.WSLSettingsPath | Should -Be ""
	}

	It "passes Sources through untouched" {
		$sources = @{ neon = @{ Repository = "MyOrg/MyMod"; Ref = "v1.0.0"; SkipPaths = @() } }

		$result = Resolve-AiModsConfig -Configuration @{ AiMods = @{ Sources = $sources } } -RepoRoot "C:\Repo"

		$result.Sources.neon.Repository | Should -Be "MyOrg/MyMod"
		$result.Sources.neon.ContainsKey('SkipPaths') | Should -BeTrue
	}

	It "resolves the repository root through Get-RepositoryPath when not given" {
		(Resolve-AiModsConfig -Configuration @{}).Root | Should -Be "C:\Repo\AI\Mods"
		Should -Invoke Get-RepositoryPath -Times 1
	}
}
