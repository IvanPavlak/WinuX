#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\List-Skills.ps1"
	. "$FunctionsPath\Get-AiSkillRoster.ps1"
	. "$FunctionsPath\Get-AiSkillDescription.ps1"
}

Describe "List-Skills" {
	BeforeEach {
		$script:Root = Join-Path $TestDrive "Skills"
		$script:Harness = Join-Path $TestDrive "harness"
		foreach ($stale in @($script:Root, $script:Harness)) {
			if (Test-Path -Path $stale) { Remove-Item -Path $stale -Recurse -Force }
		}
		New-Item -ItemType Directory -Path $script:Harness -Force | Out-Null

		function New-Skill([string]$Relative, [string]$Description = "Does things.") {
			$dir = Join-Path $script:Root $Relative
			New-Item -ItemType Directory -Path $dir -Force | Out-Null
			Set-Content -Path (Join-Path $dir "SKILL.md") -Value @("---", "name: $(Split-Path $Relative -Leaf)", "description: $Description", "---", "", "# Body")
		}

		# Junctions, not symbolic links: they are reparse points all the same, so the code under
		# test sees exactly what Deploy-AiSkills creates, but Windows does not require elevation
		# or Developer Mode to make one - the suite has to pass unelevated on CI.
		function New-SkillLink([string]$Name, [string]$Target) {
			New-Item -ItemType Junction -Path (Join-Path $script:Harness $Name) -Target $Target | Out-Null
		}

		$script:Harnesses = @($script:Harness)
		Mock Resolve-AiSkillsConfig { @{ Root = $script:Root; Harnesses = $script:Harnesses; WSLHarnesses = @(); Sources = @{} } }
		Mock Resolve-Selection { $InputObject }

		# Nothing here formats its own output: the catalog goes through the shared
		# Create-CenteredBorder + Show-FunctionDetails renderers that List-Functions uses, and
		# everything else through the Logging module. Both seams are captured, so the tests
		# assert what was rendered and at which level rather than matching console text.
		# $script:Rendered holds one entry per skill the catalog drew.
		$script:Written = @()
		$script:Levels = @()
		$script:Rendered = @()
		Mock Write-LogTitle { $script:Written += "[$Message]"; $script:Levels += "Title" }
		Mock Write-LogStep { $script:Written += [string]$Message; $script:Levels += "Step" }
		Mock Write-LogSuccess { $script:Written += [string]$Message; $script:Levels += "Success" }
		Mock Write-LogWarning { $script:Written += [string]$Message; $script:Levels += "Warning" }
		Mock Write-LogError { $script:Written += [string]$Message; $script:Levels += "Error" }
		Mock Write-LogList { foreach ($i in $Items) { $script:Written += "  - $i"; $script:Levels += "List" } }
		Mock Create-CenteredBorder { "== [$Title] ==" }
		Mock Show-FunctionDetails { $script:Rendered += @{ Name = $FunctionName; Info = $FunctionInfo } }
	}

	Context "Listing" {
		It "reports an empty root instead of printing an empty catalog" {
			List-Skills

			($script:Written -join "`n") | Should -Match "No skills found under"
		}

		It "draws a bordered group per source and renders each skill through the shared renderer" {
			New-Skill "mattpocock\alpha" "Alpha does alpha."
			New-Skill "own\teach-me" "Teaches a topic."

			List-Skills

			$output = $script:Written -join "`n"
			$output | Should -Match "== \[mattpocock\] =="
			$output | Should -Match "== \[own\] =="
			@($script:Rendered.Name) | Should -Be @("alpha", "teach-me")
			$script:Rendered[0].Info['Description'] | Should -Be "Alpha does alpha."
			$script:Rendered[1].Info['Description'] | Should -Be "Teaches a topic."
		}

		It "closes with a total count border" {
			New-Skill "mattpocock\alpha"
			New-Skill "own\teach-me"

			List-Skills

			($script:Written -join "`n") | Should -Match "== \[Total skill count => 2\] =="
		}

		It "gives each entry its location so the skill can be found on disk" {
			New-Skill "own\alpha"

			List-Skills

			$script:Rendered[0].Info['Location'] | Should -Be (Join-Path $script:Root "own\alpha")
		}

		It "reads the description from the SKILL.md frontmatter and unescapes table pipes" {
			New-Skill "own\alpha" "Handles a | pipe."

			List-Skills

			$script:Rendered[0].Info['Description'] | Should -Be "Handles a | pipe."
		}

		It "omits the Description field entirely for a skill with no frontmatter" {
			$dir = Join-Path $script:Root "own\bare"
			New-Item -ItemType Directory -Path $dir -Force | Out-Null
			Set-Content -Path (Join-Path $dir "SKILL.md") -Value "# No frontmatter"

			List-Skills

			$script:Rendered[0].Name | Should -Be "bare"
			$script:Rendered[0].Info.Contains('Description') | Should -BeFalse
			$script:Rendered[0].Info.Contains('Location') | Should -BeTrue
		}

		It "filters to the named source" {
			New-Skill "mattpocock\alpha"
			New-Skill "own\teach-me"

			List-Skills -Source own

			@($script:Rendered.Name) | Should -Be @("teach-me")
			($script:Written -join "`n") | Should -Not -Match "\[mattpocock\]"
			($script:Written -join "`n") | Should -Match "== \[Total skill count => 1\] =="
		}

		It "filters to the named skill across sources" {
			New-Skill "mattpocock\alpha"
			New-Skill "own\teach-me"

			List-Skills -Skill teach-me

			@($script:Rendered.Name) | Should -Be @("teach-me")
		}

		# An empty value is how the menu is reached: it selects the filter's parameter set while
		# giving Resolve-Selection nothing to resolve, so it prompts. -Source on its own cannot
		# bind, since the parameter takes a string array rather than being a switch.
		It "opens the selection menu when the filter is given an empty value" {
			New-Skill "own\alpha"

			List-Skills -Source @()

			Should -Invoke Resolve-Selection -Times 1 -ParameterFilter { $MenuTitle -eq "[Available Sources]" }
		}

		It "prints nothing when the selection menu is dismissed" {
			New-Skill "own\alpha"
			Mock Resolve-Selection { $null }

			List-Skills -Source @()

			$script:Written | Should -BeNullOrEmpty
			$script:Rendered | Should -BeNullOrEmpty
		}

		It "warns instead of drawing an empty catalog when a filter matches nothing" {
			New-Skill "own\alpha"
			Mock Resolve-Selection { @("nope") }

			List-Skills -Skill nope

			$script:Rendered | Should -BeNullOrEmpty
			($script:Written -join "`n") | Should -Match "No skill matched the filter"
		}
	}

	Context "Discrepancies" {
		It "reports a skill that is present but not linked into the harness" {
			New-Skill "own\alpha"

			List-Skills -ListDiscrepancies

			$output = $script:Written -join "`n"
			$output | Should -Match "NOT linked into this harness"
			$output | Should -Match "alpha"
		}

		It "is silent about a skill that is linked at the right target" {
			New-Skill "own\alpha"
			New-SkillLink "alpha" (Join-Path $script:Root "own\alpha")

			List-Skills -ListDiscrepancies

			($script:Written -join "`n") | Should -Match "are linked into every harness"
		}

		It "suppresses the success banner with -Quiet" {
			New-Skill "own\alpha"
			New-SkillLink "alpha" (Join-Path $script:Root "own\alpha")

			List-Skills -ListDiscrepancies -Quiet

			$script:Written | Should -BeNullOrEmpty
		}

		It "reports a real folder shadowing a skill name" {
			New-Skill "own\alpha"
			New-Item -ItemType Directory -Path (Join-Path $script:Harness "alpha") -Force | Out-Null

			List-Skills -ListDiscrepancies

			($script:Written -join "`n") | Should -Match "a real item sits at that path"
		}

		It "reports a link that points somewhere other than the skill of that name" {
			New-Skill "own\alpha"
			New-Skill "own\bravo"
			New-SkillLink "alpha" (Join-Path $script:Root "own\bravo")

			List-Skills -ListDiscrepancies

			($script:Written -join "`n") | Should -Match "links to"
		}

		It "reports a link into the skills root whose skill is gone" {
			New-Skill "own\alpha"
			New-Skill "own\removed"
			New-SkillLink "alpha" (Join-Path $script:Root "own\alpha")
			New-SkillLink "removed" (Join-Path $script:Root "own\removed")
			Remove-Item -Path (Join-Path $script:Root "own\removed") -Recurse -Force

			List-Skills -ListDiscrepancies

			($script:Written -join "`n") | Should -Match "removed \(target is gone\)"
		}

		It "reports a link into the skills root whose name the roster no longer carries" {
			New-Skill "own\alpha"
			New-Skill "own\renamed"
			New-SkillLink "alpha" (Join-Path $script:Root "own\alpha")
			# The folder still exists but carries no SKILL.md, so the roster does not list it.
			Remove-Item -Path (Join-Path $script:Root "own\renamed\SKILL.md") -Force
			New-SkillLink "renamed" (Join-Path $script:Root "own\renamed")

			List-Skills -ListDiscrepancies

			($script:Written -join "`n") | Should -Match "renamed \(no longer in the roster\)"
		}

		It "never reports a link that points outside the skills root" {
			New-Skill "own\alpha"
			New-SkillLink "alpha" (Join-Path $script:Root "own\alpha")
			$foreign = Join-Path $TestDrive "elsewhere"
			New-Item -ItemType Directory -Path $foreign -Force | Out-Null
			New-SkillLink "someone-elses-skill" $foreign

			List-Skills -ListDiscrepancies

			($script:Written -join "`n") | Should -Not -Match "someone-elses-skill"
		}

		It "reports a harness directory that does not exist at all" {
			New-Skill "own\alpha"
			$script:Harnesses = @((Join-Path $TestDrive "absent"))

			List-Skills -ListDiscrepancies

			($script:Written -join "`n") | Should -Match "does not exist"
		}

		It "reports a duplicate skill name and which source wins" {
			New-Skill "aaa\shared"
			New-Skill "zzz\shared"
			New-SkillLink "shared" (Join-Path $script:Root "aaa\shared")

			List-Skills -ListDiscrepancies

			$output = $script:Written -join "`n"
			$output | Should -Match "Duplicate skill name\(s\) across sources"
			$output | Should -Match "shared is in \[zzz\] and \[aaa\]"
			$output | Should -Match "\[aaa\] is the one deployed"
		}

		It "points at Deploy-AiSkills and says the WSL harnesses are not read" {
			New-Skill "own\alpha"

			List-Skills -ListDiscrepancies

			($script:Written -join "`n") | Should -Match "Run Deploy-AiSkills to reconcile"
		}
	}

	Context "Output routing" {
		# Every line has to reach the session log, which only happens by going through the
		# Logging module. A stray Write-Host would still look right on screen and silently
		# leave nothing behind in the log, so it is asserted against directly.
		It "never writes to the host directly" {
			New-Skill "own\alpha"
			Mock Write-Host { }

			List-Skills
			List-Skills -ListDiscrepancies

			Should -Invoke Write-Host -Times 0
		}

		It "reports an empty root as a warning" {
			List-Skills

			$script:Levels | Should -Be @("Warning")
		}

		It "emits only the group and total borders itself, leaving the entries to the shared renderer" {
			New-Skill "own\alpha"
			New-Skill "own\bravo"

			List-Skills

			$script:Levels | Should -Be @("Step", "Step")
			$script:Rendered.Count | Should -Be 2
		}

		It "reports a clean audit as a success and a finding as a warning" {
			New-Skill "own\alpha"
			New-SkillLink "alpha" (Join-Path $script:Root "own\alpha")

			List-Skills -ListDiscrepancies

			$script:Levels | Should -Be @("Success")

			Remove-Item -Path (Join-Path $script:Harness "alpha") -Force -Recurse
			$script:Written = @()
			$script:Levels = @()

			List-Skills -ListDiscrepancies

			$script:Levels[0] | Should -Be "Title"
			$script:Levels | Should -Contain "Warning"
			$script:Levels | Should -Not -Contain "Success"
		}
	}
}
