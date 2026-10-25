#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	# Dot-sourced so it exists to Mock even in sessions whose imported AI module predates it.
	. "$FunctionsPath\Resolve-AiArtifactsConfig.ps1"
	. "$FunctionsPath\List-AiArtifacts.ps1"
	. "$FunctionsPath\Get-AiArtifactRoster.ps1"
	. "$FunctionsPath\Get-AiArtifactPlan.ps1"
	. "$FunctionsPath\Get-AiSkillDescription.ps1"

	function New-Artifact([string]$Relative, [string]$File = "SKILL.md", [string]$Description = "Does things.") {
		$dir = Join-Path $script:Root $Relative
		New-Item -ItemType Directory -Path $dir -Force | Out-Null
		Set-Content -Path (Join-Path $dir $File) -Value @("---", "name: $(Split-Path $Relative -Leaf)", "description: $Description", "---", "", "# Body")
		$dir
	}
}

Describe "List-AiArtifacts" {
	BeforeEach {
		$script:Root = Join-Path $TestDrive "AI"
		$script:Folder = Join-Path $TestDrive "home\skills"
		foreach ($stale in @($script:Root, (Join-Path $TestDrive "home"))) {
			if (Test-Path -Path $stale) { Remove-Item -Path $stale -Recurse -Force }
		}

		$script:Harnesses = [ordered]@{
			"claude-code" = @{ Name = "claude-code"; Destinations = @(@{ Kind = "skills"; Placement = "each"; Files = @("."); Hooks = @(); Path = $script:Folder; WSLPath = "" }) }
		}
		$script:Config = @{ Root = $script:Root; Sources = @{ mattpocock = @{} }; Exclude = @(); Use = @{}; Deploy = @("claude-code"); Harnesses = $script:Harnesses; Unknown = @(); Legacy = @() }
		Mock Resolve-AiArtifactsConfig { $script:Config }
		Mock Resolve-Selection { $InputObject }

		# The catalog goes through the shared renderers and the Logging module; both seams are
		# captured, so the tests assert what was rendered rather than console text.
		$script:Rendered = @()
		$script:Lists = @()
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogList { $script:Lists += , @($Items) }
		Mock Create-CenteredBorder { "== [$Title] ==" }
		Mock Show-FunctionDetails { $script:Rendered += @{ Name = $FunctionName; Info = $FunctionInfo } }
	}

	Context "Listing" {
		It "warns and renders nothing when the repository carries no artifact" {
			List-AiArtifacts

			$script:Rendered | Should -BeNullOrEmpty
			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}

		It "renders every item through the shared renderer, grouped by kind then source, with its description" {
			New-Artifact "Skills\own\teach-me" -Description "Teaches a topic."
			New-Artifact "Skills\mattpocock\alpha"
			New-Artifact "Rules\own\CoreAiRules" "RULES.md" "House rules."

			List-AiArtifacts

			@($script:Rendered.Name) | Should -Be @("teach-me", "alpha", "CoreAiRules")
			$script:Rendered[0].Info['Description'] | Should -Be "Teaches a topic."
			$script:Rendered[2].Info['Description'] | Should -Be "House rules."
			$script:Rendered[1].Info['Location'] | Should -Be (Join-Path $script:Root "Skills\mattpocock\alpha")
			Should -Invoke Create-CenteredBorder -ParameterFilter { $Title -eq "skills - own" }
			Should -Invoke Create-CenteredBorder -ParameterFilter { $Title -eq "rules - own" }
		}

		It "reads a mod's description from its plugin.json" {
			$mod = Join-Path $script:Root "Mods\own\band"
			New-Item -ItemType Directory -Path (Join-Path $mod ".claude-plugin") -Force | Out-Null
			Set-Content -Path (Join-Path $mod ".claude-plugin\plugin.json") -Value '{"name":"band","description":"Draws a band."}'

			List-AiArtifacts -Kind Mods

			$script:Rendered[0].Info['Description'] | Should -Be "Draws a band."
		}

		It "filters by kind, by source and by name pattern" {
			New-Artifact "Skills\own\teach-me"
			New-Artifact "Skills\mattpocock\alpha"
			New-Artifact "Skills\mattpocock\tdd"
			New-Artifact "Rules\own\CoreAiRules" "RULES.md"

			List-AiArtifacts -Kind Rules
			@($script:Rendered.Name) | Should -Be @("CoreAiRules")

			$script:Rendered = @()
			List-AiArtifacts -Source mattpocock
			@($script:Rendered.Name) | Should -Be @("alpha", "tdd")

			$script:Rendered = @()
			List-AiArtifacts -Name "t*"
			@($script:Rendered.Name) | Should -Be @("teach-me", "tdd")
		}

		It "warns when a filter matches nothing" {
			New-Artifact "Skills\own\teach-me"

			List-AiArtifacts -Name "nothing*"

			$script:Rendered | Should -BeNullOrEmpty
			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}
	}

	Context "Discrepancies" {
		BeforeEach {
			$script:Alpha = New-Artifact "Skills\own\alpha"
			$script:Bravo = New-Artifact "Skills\own\bravo"
			New-Item -ItemType Directory -Path $script:Folder -Force | Out-Null
		}

		It "is silent under -Quiet and reports success otherwise when everything is deployed" {
			New-Item -ItemType Junction -Path (Join-Path $script:Folder "alpha") -Target $script:Alpha | Out-Null
			New-Item -ItemType Junction -Path (Join-Path $script:Folder "bravo") -Target $script:Bravo | Out-Null

			List-AiArtifacts -ListDiscrepancies -Quiet
			Should -Invoke Write-LogSuccess -Times 0
			Should -Invoke Write-LogWarning -Times 0

			List-AiArtifacts -ListDiscrepancies
			Should -Invoke Write-LogSuccess -Times 1 -Exactly
		}

		It "lists an item that is not deployed and one shadowed by a real folder" {
			New-Item -ItemType Directory -Path (Join-Path $script:Folder "bravo") -Force | Out-Null

			List-AiArtifacts -ListDiscrepancies

			$flat = @($script:Lists | ForEach-Object { $_ })
			$flat | Should -Contain "alpha"
			@($flat | Where-Object { $_ -like "bravo*" }).Count | Should -Be 1
			Should -Invoke Write-LogSuccess -Times 0
		}

		It "lists a stale link into the artifacts root" {
			New-Item -ItemType Junction -Path (Join-Path $script:Folder "alpha") -Target $script:Alpha | Out-Null
			New-Item -ItemType Junction -Path (Join-Path $script:Folder "bravo") -Target $script:Bravo | Out-Null
			$gone = New-Artifact "Skills\own\gone"
			New-Item -ItemType Junction -Path (Join-Path $script:Folder "gone") -Target $gone | Out-Null
			Remove-Item -Path $gone -Recurse -Force

			List-AiArtifacts -ListDiscrepancies

			@($script:Lists | ForEach-Object { $_ } | Where-Object { $_ -like "gone*" }).Count | Should -Be 1
		}

		It "reports an item name two sources carry" {
			New-Item -ItemType Junction -Path (Join-Path $script:Folder "alpha") -Target $script:Alpha | Out-Null
			New-Item -ItemType Junction -Path (Join-Path $script:Folder "bravo") -Target $script:Bravo | Out-Null
			New-Artifact "Skills\mattpocock\alpha"

			List-AiArtifacts -ListDiscrepancies

			@($script:Lists | ForEach-Object { $_ } | Where-Object { $_ -like "skills/alpha*" }).Count | Should -Be 1
		}
	}
}
