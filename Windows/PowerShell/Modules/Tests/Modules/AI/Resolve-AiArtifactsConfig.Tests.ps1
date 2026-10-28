#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Resolve-AiArtifactsConfig.ps1"

	# A small catalogue in the base shape: Claude Code with a {User} folder, a {User} file and an
	# explicit WSL path; Codex with one Work-only destination.
	function New-Harnesses {
		@{
			"claude-code" = @{
				WSL          = $true
				Destinations = @(
					@{ Kind = "Skills"; Placement = "Each"; Files = @("."); Path = "{User}\.claude\skills" }
					@{ Kind = "Rules"; Placement = "File"; Files = @("RULES.md"); Path = "{User}\.claude\CLAUDE.md" }
					@{ Kind = "Rules"; Placement = "File"; Files = @("managed-settings.json"); Hooks = @("managed-settings"); Path = "C:\Program Files\ClaudeCode\managed-settings.json"; WSLPath = "/etc/claude-code/managed-settings.json" }
					@{ Kind = "Prompts"; Placement = "Each"; Files = @("PROMPT.md"); Path = "D:\literal\prompts" }
				)
			}
			codex         = @{
				Destinations = @(
					@{ Kind = "Skills"; Placement = "Each"; Files = @("."); Path = "{User}\.agents\skills" }
					@{ Kind = "Agents"; Placement = "Each"; Files = @("codex.toml"); Path = "{User}\.codex\agents"; Machine = "Work" }
				)
			}
		}
	}
}

Describe "Resolve-AiArtifactsConfig" {
	BeforeEach {
		# Test-MachineTypeScope validates tokens against the global ValidMachineTypes; none here.
		$global:Configuration = @{}
		Mock Get-RepositoryPath { @{ Repo = "C:\Repo" } }
		Mock Write-LogError { }
	}

	It "falls back to the built-in defaults on an empty configuration and deploys nothing" {
		$result = Resolve-AiArtifactsConfig -Configuration @{} -RepoRoot "C:\Repo" -MachineType PC

		$result.Root | Should -Be "C:\Repo\AI"
		$result.Sources.Count | Should -Be 0
		$result.Exclude | Should -BeNullOrEmpty
		$result.Use.Count | Should -Be 0
		$result.Deploy | Should -BeNullOrEmpty
		$result.Harnesses.Count | Should -Be 0
	}

	It "picks the machine type's Deploy list over Default" {
		$config = @{ AiHarnesses = New-Harnesses; AiArtifacts = @{ Deploy = @{ Default = @("claude-code", "codex"); Work = @("codex") } } }

		(Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType Work).Deploy | Should -Be @("codex")
		(Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC).Deploy | Should -Be @("claude-code", "codex")
	}

	It "reports Deploy names without an AiHarnesses entry and resolves only the known ones" {
		$config = @{ AiHarnesses = New-Harnesses; AiArtifacts = @{ Deploy = @{ Default = @("claude-code", "t3") } } }

		$result = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC

		$result.Unknown | Should -Be @("t3")
		@($result.Harnesses.Keys) | Should -Be @("claude-code")
	}

	It "lowercases Exclude strings and keeps a machine-scoped entry only on its machine type" {
		$config = @{ AiArtifacts = @{ Exclude = @("Skills/TDD", @{ Item = "rules/example/CoreAiRules"; Machine = "Work" }) } }

		(Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC).Exclude | Should -Be @("skills/tdd")
		(Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType Work).Exclude | Should -Be @("skills/tdd", "rules/example/coreairules")
	}

	It "reads Use per kind, a value optionally per machine type" {
		$config = @{ AiArtifacts = @{ Use = @{ Rules = @{ Default = "CoreAiRules"; Work = "WorkRules" }; Prompts = "Review" } } }

		$pc = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC
		$work = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType Work

		$pc.Use['rules'] | Should -Be "CoreAiRules"
		$pc.Use['prompts'] | Should -Be "Review"
		$work.Use['rules'] | Should -Be "WorkRules"
	}

	It "expands the destinations and keeps only the ones whose Machine scope matches" {
		$config = @{ AiHarnesses = New-Harnesses; AiArtifacts = @{ Deploy = @{ Default = @("codex") } } }

		$pc = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC
		$work = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType Work

		@($pc.Harnesses['codex'].Destinations).Count | Should -Be 1
		$pc.Harnesses['codex'].Destinations[0].Path | Should -Be "$env:USERPROFILE\.agents\skills"
		$pc.Harnesses['codex'].Destinations[0].Kind | Should -Be "skills"
		$pc.Harnesses['codex'].Destinations[0].Placement | Should -Be "each"
		@($work.Harnesses['codex'].Destinations).Count | Should -Be 2
	}

	It "derives WSL twins from {User} paths, takes an explicit WSLPath, and gives other paths none" {
		$config = @{ DefaultWSLUsername = "you"; AiHarnesses = New-Harnesses; AiArtifacts = @{ Deploy = @{ Default = @("claude-code") } } }

		$destinations = (Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC).Harnesses['claude-code'].Destinations

		$destinations[0].WSLPath | Should -Be "/home/you/.claude/skills"
		$destinations[1].WSLPath | Should -Be "/home/you/.claude/CLAUDE.md"
		$destinations[2].WSLPath | Should -Be "/etc/claude-code/managed-settings.json"
		$destinations[2].Hooks | Should -Be @("managed-settings")
		$destinations[3].WSLPath | Should -Be ""
	}

	It "gives no WSL twin without DefaultWSLUsername or for a harness without WSL" {
		$config = @{ AiHarnesses = New-Harnesses; AiArtifacts = @{ Deploy = @{ Default = @("claude-code", "codex") } } }
		$noUser = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC
		@($noUser.Harnesses['claude-code'].Destinations | Where-Object { $_.WSLPath }).Count | Should -Be 0

		$config.DefaultWSLUsername = "you"
		$withUser = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC
		@($withUser.Harnesses['codex'].Destinations | Where-Object { $_.WSLPath }).Count | Should -Be 0
	}

	It "gives a source without a kind key the skills folder" {
		$config = @{ AiArtifacts = @{ Sources = @{ plain = @{ Repository = "A/B" } } } }

		(Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC).Sources['plain'].Kinds['skills'] | Should -Be @("skills")
	}
}
