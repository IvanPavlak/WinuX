#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Get-AiArtifactPlan.ps1"
	# The real roster, so the plan is built from the same walk Deploy-AiArtifacts uses.
	. "$FunctionsPath\Get-AiArtifactRoster.ps1"

	function New-ArtifactFile([string]$Relative, [string]$File) {
		$dir = Join-Path $script:Root $Relative
		New-Item -ItemType Directory -Path $dir -Force | Out-Null
		Set-Content -Path (Join-Path $dir $File) -Value "content"
	}

	function New-Destination([string]$Kind, [string]$Placement, [string[]]$Files, [string]$Path, [string]$WSLPath = "") {
		@{ Kind = $Kind; Placement = $Placement; Files = $Files; Hooks = @(); Path = $Path; WSLPath = $WSLPath }
	}
}

Describe "Get-AiArtifactPlan" {
	BeforeEach {
		$script:Root = Join-Path $TestDrive "AI"
		$script:UserDir = Join-Path $TestDrive "home"
		foreach ($stale in @($script:Root, $script:UserDir)) {
			if (Test-Path -Path $stale) { Remove-Item -Path $stale -Recurse -Force }
		}

		New-ArtifactFile "Skills\own\alpha" "SKILL.md"
		New-ArtifactFile "Skills\own\bravo" "SKILL.md"
		New-ArtifactFile "Agents\own\reviewer" "claude.md"
		New-ArtifactFile "Agents\own\reviewer" "copilot.agent.md"
		New-ArtifactFile "Agents\own\planner" "AGENT.md"
		New-ArtifactFile "Rules\own\CoreAiRules" "RULES.md"

		$script:Harnesses = [ordered]@{}
		$script:Config = @{
			Root      = $script:Root
			Sources   = @{}
			Exclude   = @()
			Use       = @{ rules = "CoreAiRules" }
			Deploy    = @()
			Harnesses = $script:Harnesses
			Unknown   = @()
		}
	}

	It "plans one link per item in an Each destination that takes the folder itself" {
		$script:Harnesses['claude-code'] = @{ Name = "claude-code"; Destinations = @(New-Destination "skills" "each" @(".") "$script:UserDir\.claude\skills" "/home/you/.claude/skills") }

		$plan = Get-AiArtifactPlan -Config $script:Config

		$plan.Destinations.Count | Should -Be 1
		$items = $plan.Destinations[0].Items
		@($items.Name) | Should -Be @("alpha", "bravo")
		$items[0].Source | Should -Be (Join-Path $script:Root "Skills\own\alpha")
		$items[0].Target | Should -Be "$script:UserDir\.claude\skills\alpha"
		$items[0].WSLTarget | Should -Be "/home/you/.claude/skills/alpha"
	}

	It "takes the first listed file an item has and names the link after the item plus its extension" {
		$script:Harnesses['claude-code'] = @{ Name = "claude-code"; Destinations = @(New-Destination "agents" "each" @("claude.md", "AGENT.md") "$script:UserDir\.claude\agents") }
		$script:Harnesses['copilot'] = @{ Name = "copilot"; Destinations = @(New-Destination "agents" "each" @("copilot.agent.md") "$script:UserDir\.copilot\agents") }

		$plan = Get-AiArtifactPlan -Config $script:Config

		$claude = $plan.Destinations[0].Items
		@($claude.Target | ForEach-Object { Split-Path $_ -Leaf }) | Should -Be @("planner.md", "reviewer.md")
		($claude | Where-Object { $_.Name -eq "reviewer" }).Source | Should -Be (Join-Path $script:Root "Agents\own\reviewer\claude.md")
		($claude | Where-Object { $_.Name -eq "planner" }).Source | Should -Be (Join-Path $script:Root "Agents\own\planner\AGENT.md")
		$copilot = $plan.Destinations[1].Items
		@($copilot.Name) | Should -Be @("reviewer") -Because "an item without the file is left out of that destination"
		Split-Path $copilot[0].Target -Leaf | Should -Be "reviewer.agent.md"
		$copilot[0].WSLTarget | Should -Be ""
	}

	It "plans a destination two harnesses name once, and warns when they define it differently" {
		$shared = "$script:UserDir\.agents\skills"
		$script:Harnesses['codex'] = @{ Name = "codex"; Destinations = @(New-Destination "skills" "each" @(".") $shared) }
		$script:Harnesses['gemini-cli'] = @{ Name = "gemini-cli"; Destinations = @(New-Destination "skills" "each" @(".") $shared.ToUpperInvariant()) }
		$script:Harnesses['copilot'] = @{ Name = "copilot"; Destinations = @(New-Destination "skills" "copy" @(".") $shared) }

		$plan = Get-AiArtifactPlan -Config $script:Config

		$plan.Destinations.Count | Should -Be 1
		$plan.Destinations[0].Harness | Should -Be "codex"
		$plan.Warnings.Count | Should -Be 1 -Because "only copilot defines the shared folder differently"
	}

	It "links the Use item into a File destination" {
		$script:Harnesses['codex'] = @{ Name = "codex"; Destinations = @(New-Destination "rules" "file" @("RULES.md") "$script:UserDir\.codex\AGENTS.md" "/home/you/.codex/AGENTS.md") }

		$plan = Get-AiArtifactPlan -Config $script:Config

		$item = @($plan.Destinations[0].Items)
		$item.Count | Should -Be 1
		$item[0].Source | Should -Be (Join-Path $script:Root "Rules\own\CoreAiRules\RULES.md")
		$item[0].Target | Should -Be "$script:UserDir\.codex\AGENTS.md"
		$item[0].WSLTarget | Should -Be "/home/you/.codex/AGENTS.md"
	}

	It "leaves a File destination empty without a Use entry, with a Use naming no item, or without the file" {
		$script:Harnesses['claude-code'] = @{ Name = "claude-code"; Destinations = @(
				New-Destination "rules" "file" @("managed-settings.json") "$script:UserDir\managed-settings.json"
				New-Destination "agents" "file" @("AGENT.md") "$script:UserDir\agent.md"
			)
		}

		$plan = Get-AiArtifactPlan -Config $script:Config
		@($plan.Destinations | ForEach-Object { $_.Items.Count }) | Should -Be @(0, 0)
		$plan.Warnings | Should -BeNullOrEmpty
		$plan.Notes.Count | Should -Be 2 -Because "the rules item lacks the file and agents have no Use entry"

		$script:Config.Use = @{ rules = "Missing" }
		$plan = Get-AiArtifactPlan -Config $script:Config
		$plan.Destinations[0].Items.Count | Should -Be 0
		$plan.Warnings.Count | Should -Be 1
	}

	It "limits the plan to the kinds given" {
		$script:Harnesses['claude-code'] = @{ Name = "claude-code"; Destinations = @(
				New-Destination "skills" "each" @(".") "$script:UserDir\skills"
				New-Destination "rules" "file" @("RULES.md") "$script:UserDir\CLAUDE.md"
			)
		}

		$plan = Get-AiArtifactPlan -Kind Rules -Config $script:Config

		@($plan.Destinations.Kind) | Should -Be @("rules")
	}

	It "warns on an unknown harness and an incomplete destination, and skips both" {
		$script:Config.Unknown = @("t3")
		$script:Harnesses['broken'] = @{ Name = "broken"; Destinations = @(New-Destination "widgets" "each" @(".") "$script:UserDir\w") }

		$plan = Get-AiArtifactPlan -Config $script:Config

		$plan.Destinations | Should -BeNullOrEmpty
		$plan.Warnings.Count | Should -Be 2
	}
}
