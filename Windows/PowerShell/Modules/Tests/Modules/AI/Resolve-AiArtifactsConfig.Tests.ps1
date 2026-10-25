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
		$result.Legacy | Should -BeNullOrEmpty
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

	Context "deprecated keys" {
		It "maps AiSkills.Sources onto sources with the skills kind" {
			$config = @{ AiSkills = @{ Sources = @{ mattpocock = @{ Repository = "OWNER/skills"; Folders = @("skills/engineering"); Exclude = @("tdd") } } } }

			$result = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC

			$source = $result.Sources['mattpocock']
			$source.Repository | Should -Be "OWNER/skills"
			$source.Ref | Should -Be "main"
			$source.Kinds['skills'] | Should -Be @("skills/engineering")
			$source.Exclude | Should -Be @("tdd")
			@($result.Legacy).Count | Should -Be 2 -Because "the source and the implied Deploy fallback are both reported"
		}

		It "maps AiMods.Sources onto the mods kind with a root default, Exclude and SkipPaths" {
			$config = @{ AiMods = @{ Sources = @{ "my-mod" = @{ Repository = "MyOrg/MyMod"; Ref = "v1"; Exclude = @("old"); SkipPaths = @() } } } }

			$source = (Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC).Sources['my-mod']

			$source.Ref | Should -Be "v1"
			$source.Kinds['mods'] | Should -Be @(".")
			$source.Exclude | Should -Be @("old")
			$source.SkipPaths | Should -BeNullOrEmpty
		}

		It "lets an AiArtifacts.Sources entry win over a deprecated source of the same name" {
			$config = @{
				AiArtifacts = @{ Sources = @{ shared = @{ Repository = "New/Repo"; Agents = @("agents") } } }
				AiSkills    = @{ Sources = @{ shared = @{ Repository = "Old/Repo" } } }
			}

			$source = (Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC).Sources['shared']

			$source.Repository | Should -Be "New/Repo"
			@($source.Kinds.Keys) | Should -Be @("agents")
		}

		It "gives a source without a kind key the skills folder" {
			$config = @{ AiArtifacts = @{ Sources = @{ plain = @{ Repository = "A/B" } } } }

			(Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC).Sources['plain'].Kinds['skills'] | Should -Be @("skills")
		}

		It "moves Root to the parent of a non-default AiSkills.Root" {
			$config = @{ AiSkills = @{ Root = "{RepoRoot}\Elsewhere\Skills" } }

			$result = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC

			$result.Root | Should -Be "C:\Repo\Elsewhere"
			@($result.Legacy).Count | Should -Be 1
		}

		It "leaves Root alone for the shipped AiSkills.Root default" {
			$config = @{ AiSkills = @{ Root = "{RepoRoot}\AI\Skills" } }

			$result = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC

			$result.Root | Should -Be "C:\Repo\AI"
			$result.Legacy | Should -BeNullOrEmpty
		}

		It "falls back to claude-code, codex and gemini-cli when a deprecated step is on and Deploy lists nothing" -TestCases @(
			@{ Step = "AiSkills"; Value = $true }
			@{ Step = "CoreAiRules"; Value = $true }
			@{ Step = "AiMods"; Value = @{ Default = $false; PC = $true } }
		) {
			param($Step, $Value)
			$config = @{ BootstrapConfig = @{ Steps = @{ $Step = $Value } } }

			$result = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC

			$result.Deploy | Should -Be @("claude-code", "codex", "gemini-cli")
			@($result.Legacy).Count | Should -Be 1
		}

		It "does not fall back when the deprecated step is off for this machine type" {
			$config = @{ BootstrapConfig = @{ Steps = @{ AiSkills = @{ Default = $true; Work = $false } } } }

			(Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType Work).Deploy | Should -BeNullOrEmpty
		}

		It "falls back when only deprecated sources are configured" {
			$config = @{ AiMods = @{ Sources = @{ m = @{ Repository = "A/B" } } } }

			(Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC).Deploy | Should -Be @("claude-code", "codex", "gemini-cli")
		}

		It "keeps the configured Deploy list when one is set" {
			$config = @{
				AiArtifacts     = @{ Deploy = @{ Default = @("copilot") } }
				BootstrapConfig = @{ Steps = @{ AiSkills = $true } }
				AiSkills        = @{ Sources = @{ s = @{ Repository = "A/B" } } }
			}

			(Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC).Deploy | Should -Be @("copilot")
		}

		It "reads the rules item a SymbolicLinks.AI entry targets as Use.Rules when Use names none" {
			$config = @{ PathTemplates = @{ SymbolicLinks = @{ AI = @{ Claude = @{ Path = "{User}\.claude\CLAUDE.md"; Target = "{RepoRoot}\AI\Rules\own\MyRules\RULES.md" } } } } }

			$result = Resolve-AiArtifactsConfig -Configuration $config -RepoRoot "C:\Repo" -MachineType PC

			$result.Use['rules'] | Should -Be "MyRules"
			@($result.Legacy).Count | Should -Be 1
		}
	}
}
