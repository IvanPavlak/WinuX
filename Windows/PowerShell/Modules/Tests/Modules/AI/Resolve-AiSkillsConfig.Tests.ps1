#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Resolve-AiSkillsConfig.ps1"
}

Describe "Resolve-AiSkillsConfig" {
	BeforeEach {
		Mock Get-RepositoryPath { @{ Repo = "C:\Repo" } }
	}

	It "falls back to the built-in defaults when the section is missing" {
		$result = Resolve-AiSkillsConfig -Configuration @{} -RepoRoot "C:\Repo"

		$result.Root | Should -Be "C:\Repo\AI\Skills"
		$result.Harnesses | Should -Be @("$env:USERPROFILE\.claude\skills", "$env:USERPROFILE\.agents\skills")
		$result.WSLHarnesses | Should -BeNullOrEmpty
		$result.Sources.Count | Should -Be 0
	}

	It "expands {RepoRoot}, {User} and {AppData} in Root and Harnesses" {
		$config = @{
			AiSkills = @{
				Root      = "{RepoRoot}\Elsewhere\Skills"
				Harnesses = @("{User}\.claude\skills", "{AppData}\tool\skills", "D:\literal\skills")
			}
		}

		$result = Resolve-AiSkillsConfig -Configuration $config -RepoRoot "C:\Repo"

		$result.Root | Should -Be "C:\Repo\Elsewhere\Skills"
		$result.Harnesses | Should -Be @("$env:USERPROFILE\.claude\skills", "$env:APPDATA\tool\skills", "D:\literal\skills")
	}

	It "derives WSL harness paths from the {User} entries and DefaultWSLUsername" {
		$config = @{
			DefaultWSLUsername = "you"
			AiSkills           = @{
				Harnesses = @("{User}\.claude\skills", "{User}\.agents\skills", "D:\literal\skills")
			}
		}

		$result = Resolve-AiSkillsConfig -Configuration $config -RepoRoot "C:\Repo"

		$result.WSLHarnesses | Should -Be @("/home/you/.claude/skills", "/home/you/.agents/skills")
	}

	It "yields no WSL harnesses when DefaultWSLUsername is empty" {
		$config = @{
			DefaultWSLUsername = ""
			AiSkills           = @{ Harnesses = @("{User}\.claude\skills") }
		}

		(Resolve-AiSkillsConfig -Configuration $config -RepoRoot "C:\Repo").WSLHarnesses | Should -BeNullOrEmpty
	}

	It "passes Sources through untouched" {
		$sources = @{ mattpocock = @{ Repository = "mattpocock/skills"; Ref = "main" } }

		$result = Resolve-AiSkillsConfig -Configuration @{ AiSkills = @{ Sources = $sources } } -RepoRoot "C:\Repo"

		$result.Sources.mattpocock.Repository | Should -Be "mattpocock/skills"
	}

	It "resolves the repository root through Get-RepositoryPath when not given" {
		(Resolve-AiSkillsConfig -Configuration @{}).Root | Should -Be "C:\Repo\AI\Skills"
		Should -Invoke Get-RepositoryPath -Times 1
	}
}
