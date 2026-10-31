#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Resolve-AiArtifactsConfig.ps1"
	# Profiles resolve for real from the synthetic configurations (none: profiles off).
	. "$FunctionsPath\Resolve-AiProfile.ps1"

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

	It "resolves checkout and manifest sources, expanding {Dev} to the folder holding the repository" {
		$config = @{ AiArtifacts = @{
				Checkouts = @{ myskills = @{ Path = "{Dev}\MySkills" }; agents = @{ Path = "{Dev}\MyAgents"; Agents = @("agents") } }
				Manifests = @{ thirdparty = @{ Path = "{Dev}\MySkills\third-party\manifest.tsv" }; plain = "{RepoRoot}\manifest.tsv" }
			}
		}

		$result = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Dev\Repo" -MachineType PC

		$result.Checkouts['myskills'].Path | Should -Be "C:\Dev\MySkills"
		$result.Checkouts['myskills'].Kinds['skills'] | Should -Be @("skills")
		$result.Checkouts['agents'].Kinds.Contains('skills') | Should -BeFalse
		$result.Manifests['thirdparty'].Path | Should -Be "C:\Dev\MySkills\third-party\manifest.tsv"
		$result.Manifests['plain'].Path | Should -Be "C:\Dev\Repo\manifest.tsv"
		$result.CacheRoot | Should -BeLike "*\WinuX\ai-manifests"
	}

	It "expands {Dev} from BasePaths of the machine type when it is set" {
		$config = @{ BasePaths = @{ PC = @{ Dev = "D:\Code" } }; AiArtifacts = @{ Checkouts = @{ myskills = @{ Path = "{Dev}\MySkills" } } } }

		(Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Dev\Repo" -MachineType PC).Checkouts['myskills'].Path | Should -Be "D:\Code\MySkills"
	}

	It "lets an active AI profile's Rules and Deploy win, add its excludes and carry its includes" {
		$config = @{ AiHarnesses = New-Harnesses; AiArtifacts = @{ Use = @{ Rules = "CoreAiRules" }; Exclude = @("skills/tdd"); Deploy = @{ Default = @("claude-code", "codex") } } }
		$aiProfile = @{ Enabled = $true; Name = "Work"; Profile = @{ Rules = "MyWorkRules"; Deploy = @("codex"); Exclude = @("skills/grill"); Include = @("skills/own/*") } }

		$result = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC -AiProfile $aiProfile

		$result.Use['rules'] | Should -Be "MyWorkRules"
		$result.Deploy | Should -Be @("codex")
		$result.Exclude | Should -Be @("skills/tdd", "skills/grill")
		$result.Include | Should -Be @("skills/own/*")
		$result.Profile.Name | Should -Be "Work"
	}

	It "keeps the machine-type forms when the profile sets no Deploy or Rules, and when profiles are off" {
		$config = @{ AiHarnesses = New-Harnesses; AiArtifacts = @{ Use = @{ Rules = "CoreAiRules" }; Deploy = @{ Default = @("claude-code") } } }
		$aiProfile = @{ Enabled = $true; Name = "Personal"; Profile = @{ Rules = ""; Deploy = $null; Exclude = @(); Include = @() } }

		$withProfile = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC -AiProfile $aiProfile
		$withProfile.Use['rules'] | Should -Be "CoreAiRules"
		$withProfile.Deploy | Should -Be @("claude-code")

		$off = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC -AiProfile @{ Enabled = $false }
		$off.Use['rules'] | Should -Be "CoreAiRules"
	}
}
