#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	# Dot-sourced so it exists to Mock even in sessions whose imported AI module predates it.
	. "$FunctionsPath\Resolve-AiArtifactsConfig.ps1"
	. "$FunctionsPath\Get-AiArtifactPlan.ps1"
	. "$FunctionsPath\Deploy-AiArtifacts.ps1"
	# The pure merge of the plugin list is exercised for real; the settings writer is mocked.
	. "$FunctionsPath\Resolve-AiModsPluginDirs.ps1"

	function New-PlanDestination([string]$Kind, [string]$Placement, [string]$Path, [object[]]$Items, [string[]]$Hooks = @(), [string]$WSLPath = "", [string]$Harness = "claude-code") {
		@{ Harness = $Harness; Kind = $Kind; Placement = $Placement; Hooks = $Hooks; Path = $Path; WSLPath = $WSLPath; Items = $Items }
	}

	function New-PlanItem([string]$Kind, [string]$Name, [string]$Source, [string]$Target, [string]$WSLTarget = "") {
		@{ Kind = $Kind; Name = $Name; Source = $Source; Target = $Target; WSLTarget = $WSLTarget }
	}

	function New-Skill([string]$Name) {
		$dir = Join-Path $script:Root "Skills\own\$Name"
		New-Item -ItemType Directory -Path $dir -Force | Out-Null
		Set-Content -Path (Join-Path $dir "SKILL.md") -Value $Name
		$dir
	}
}

Describe "Deploy-AiArtifacts" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogDebug { }

		$script:Repo = Join-Path $TestDrive "Repo"
		$script:Root = Join-Path $script:Repo "AI"
		$script:UserDir = Join-Path $TestDrive "home"
		foreach ($stale in @($script:Repo, $script:UserDir, (Join-Path $TestDrive "elsewhere"))) {
			if (Test-Path -Path $stale) { Remove-Item -Path $stale -Recurse -Force }
		}
		New-Item -ItemType Directory -Path $script:UserDir -Force | Out-Null
		$script:Folder = Join-Path $script:UserDir ".claude\skills"
		$script:Alpha = New-Skill "alpha"
		$script:Bravo = New-Skill "bravo"

		# The settings file is derived from the user profile, so the profile points into TestDrive.
		$script:SavedUserProfile = $env:USERPROFILE
		$env:USERPROFILE = $script:UserDir

		$global:Configuration = @{ DefaultWSLDistribution = "Ubuntu" }
		$script:Config = @{ Root = $script:Root; Deploy = @("claude-code"); WSLUser = "you" }
		$script:Destinations = @(
			New-PlanDestination "skills" "each" $script:Folder @(
				New-PlanItem "skills" "alpha" $script:Alpha (Join-Path $script:Folder "alpha")
				New-PlanItem "skills" "bravo" $script:Bravo (Join-Path $script:Folder "bravo")
			)
		)
		Mock Resolve-AiArtifactsConfig { $script:Config }
		Mock Get-AiArtifactPlan { @{ Destinations = $script:Destinations; Warnings = @(); Notes = @() } }
		Mock Get-RepositoryPath { @{ Repo = $script:Repo } }
		Mock Test-AdminPrivileges { }
		Mock Backup-RepositoryItem { Join-Path $TestDrive "backup" }
		Mock Set-ClaudeSettingsEnv { $true }
		Mock Test-AiModsCli { @{ Installed = $true; Invalid = @() } }
		Mock Test-WSLDistributionInstalled { $false }
		$script:WSLCalls = @()
		Mock wsl {
			$script:WSLCalls += , @($args)
			$global:LASTEXITCODE = 0
		}
		# Junctions stand in for the symbolic links: reparse points all the same, but creatable
		# without elevation or Developer Mode.
		Mock New-WindowsSymbolicLink {
			if (-not (Test-Path -LiteralPath $Target -PathType Container)) { return }
			$existing = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
			if ($existing) { $existing.Delete() }
			New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
		}
	}

	AfterEach {
		$env:USERPROFILE = $script:SavedUserProfile
	}

	It "does nothing when no harness is deployed into" {
		$script:Config.Deploy = @()

		Deploy-AiArtifacts

		Should -Invoke Get-AiArtifactPlan -Times 0
		Should -Invoke New-WindowsSymbolicLink -Times 0
	}

	It "creates the folder and links every item of the plan into it" {
		Deploy-AiArtifacts

		Test-Path -Path $script:Folder -PathType Container | Should -BeTrue
		Should -Invoke Test-AdminPrivileges -Times 1 -Exactly
		Should -Invoke New-WindowsSymbolicLink -Times 2 -Exactly
		Should -Invoke New-WindowsSymbolicLink -Times 1 -Exactly -ParameterFilter { $Path -eq (Join-Path $script:Folder "alpha") -and $Target -eq $script:Alpha }
		Should -Invoke Write-LogError -Times 0
	}

	It "passes the kinds through to the plan" {
		Deploy-AiArtifacts -Kind Rules, Skills

		Should -Invoke Get-AiArtifactPlan -Times 1 -Exactly -ParameterFilter { (@($Kind) -join ',') -eq 'Rules,Skills' }
	}

	It "leaves a link that already points at its item alone" {
		New-Item -ItemType Directory -Path $script:Folder -Force | Out-Null
		New-Item -ItemType Junction -Path (Join-Path $script:Folder "alpha") -Target $script:Alpha | Out-Null

		Deploy-AiArtifacts

		Should -Invoke New-WindowsSymbolicLink -Times 0 -ParameterFilter { $Path -like "*alpha" }
		Should -Invoke New-WindowsSymbolicLink -Times 1 -Exactly -ParameterFilter { $Path -like "*bravo" }
	}

	It "replaces a folder link into the repository with a real folder" {
		$old = Join-Path $script:Repo "old-skills"
		New-Item -ItemType Directory -Path $old -Force | Out-Null
		Set-Content -Path (Join-Path $old "keep.txt") -Value "keep"
		New-Item -ItemType Directory -Path (Split-Path $script:Folder) -Force | Out-Null
		New-Item -ItemType Junction -Path $script:Folder -Target $old | Out-Null

		Deploy-AiArtifacts

		(Get-Item -LiteralPath $script:Folder -Force).Attributes -band [IO.FileAttributes]::ReparsePoint | Should -Be 0
		Test-Path -Path (Join-Path $old "keep.txt") | Should -BeTrue -Because "only the link is removed, never its target"
		Should -Invoke New-WindowsSymbolicLink -Times 2 -Exactly
	}

	It "skips a folder that links somewhere WinuX does not manage" {
		$elsewhere = Join-Path $TestDrive "elsewhere"
		New-Item -ItemType Directory -Path $elsewhere -Force | Out-Null
		New-Item -ItemType Directory -Path (Split-Path $script:Folder) -Force | Out-Null
		New-Item -ItemType Junction -Path $script:Folder -Target $elsewhere | Out-Null

		Deploy-AiArtifacts

		Should -Invoke New-WindowsSymbolicLink -Times 0
		Should -Invoke Write-LogError -Times 1 -Exactly -Because "the run reports its failure count"
	}

	It "replaces a link whose target is gone or wrong, which New-WindowsSymbolicLink would not remove" {
		# The real New-WindowsSymbolicLink leaves any existing link in place when Test-Path is
		# false for it (a dangling link), so this mock refuses to create over anything at the path.
		Mock New-WindowsSymbolicLink {
			if (Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue) { return }
			New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
		}
		New-Item -ItemType Directory -Path $script:Folder -Force | Out-Null
		# Where alpha used to live (another source folder), so the link dangles while the skill itself exists.
		$moved = Join-Path $script:Root "Skills\winux\alpha"
		New-Item -ItemType Directory -Path $moved -Force | Out-Null
		New-Item -ItemType Junction -Path (Join-Path $script:Folder "alpha") -Target $moved | Out-Null
		Remove-Item -Path $moved -Recurse -Force
		$elsewhere = Join-Path $TestDrive "elsewhere\bravo"
		New-Item -ItemType Directory -Path $elsewhere -Force | Out-Null
		New-Item -ItemType Junction -Path (Join-Path $script:Folder "bravo") -Target $elsewhere | Out-Null

		Deploy-AiArtifacts

		(Get-Item -LiteralPath (Join-Path $script:Folder "alpha") -Force).LinkTarget.TrimEnd('\') | Should -Be $script:Alpha.TrimEnd('\')
		(Get-Item -LiteralPath (Join-Path $script:Folder "bravo") -Force).LinkTarget.TrimEnd('\') | Should -Be $script:Bravo.TrimEnd('\')
		Test-Path -LiteralPath $elsewhere | Should -BeTrue
	}

	It "prunes dangling links into the artifacts root and leaves other links alone" {
		New-Item -ItemType Directory -Path $script:Folder -Force | Out-Null
		$gone = Join-Path $script:Root "Skills\own\gone"
		$foreign = Join-Path $TestDrive "elsewhere\gone"
		foreach ($target in @($gone, $foreign)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
		New-Item -ItemType Junction -Path (Join-Path $script:Folder "gone") -Target $gone | Out-Null
		New-Item -ItemType Junction -Path (Join-Path $script:Folder "foreign") -Target $foreign | Out-Null
		Remove-Item -Path $gone, $foreign -Recurse -Force

		Deploy-AiArtifacts

		Get-Item -LiteralPath (Join-Path $script:Folder "gone") -Force -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
		Get-Item -LiteralPath (Join-Path $script:Folder "foreign") -Force -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
	}

	It "copies an item into a Copy destination, backing up a real item that differs" {
		$target = Join-Path $script:Folder "alpha"
		New-Item -ItemType Directory -Path $target -Force | Out-Null
		Set-Content -Path (Join-Path $target "SKILL.md") -Value "local edit"
		$script:Destinations = @(New-PlanDestination "skills" "copy" $script:Folder @(New-PlanItem "skills" "alpha" $script:Alpha $target))

		Deploy-AiArtifacts

		Should -Invoke Backup-RepositoryItem -Times 1 -Exactly -ParameterFilter { $Path -eq $target }
		Get-Content -Path (Join-Path $target "SKILL.md") | Should -Be "alpha"
		(Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint | Should -Be 0
		Should -Invoke New-WindowsSymbolicLink -Times 0
	}

	It "leaves a copy that matches the repository alone" {
		$target = Join-Path $script:Folder "alpha"
		New-Item -ItemType Directory -Path $script:Folder -Force | Out-Null
		Copy-Item -Path $script:Alpha -Destination $target -Recurse
		$script:Destinations = @(New-PlanDestination "skills" "copy" $script:Folder @(New-PlanItem "skills" "alpha" $script:Alpha $target))

		Deploy-AiArtifacts

		Should -Invoke Backup-RepositoryItem -Times 0
	}

	It "changes nothing and asks for no rights under -WhatIf" {
		Deploy-AiArtifacts -WhatIf

		Should -Invoke Test-AdminPrivileges -Times 0
		Should -Invoke New-WindowsSymbolicLink -Times 0
		Test-Path -Path $script:Folder | Should -BeFalse
	}

	It "lists the links in CLAUDE_CODE_PLUGIN_DIRS through the claude-plugin-dirs hook, ';'-separated" {
		$mods = Join-Path $script:UserDir ".claude\mods"
		$script:Destinations = @(New-PlanDestination "mods" "each" $mods @(
				New-PlanItem "mods" "alpha" $script:Alpha (Join-Path $mods "alpha")
				New-PlanItem "mods" "bravo" $script:Bravo (Join-Path $mods "bravo")
			) -Hooks @("claude-plugin-dirs"))

		Deploy-AiArtifacts

		$expected = "$(Join-Path $mods 'alpha');$(Join-Path $mods 'bravo')"
		Should -Invoke Set-ClaudeSettingsEnv -Times 1 -Exactly -ParameterFilter { $Name -eq 'CLAUDE_CODE_PLUGIN_DIRS' -and $Value -eq $expected -and $SettingsPath -eq (Join-Path $script:UserDir ".claude\settings.json") }
		Should -Invoke Test-AiModsCli -Times 1 -Exactly
	}

	It "does not run the hook for a destination without it" {
		Deploy-AiArtifacts

		Should -Invoke Set-ClaudeSettingsEnv -Times 0
	}

	Context "WSL twins" {
		BeforeEach {
			Mock Test-WSLDistributionInstalled { $true }
			$rulesSource = Join-Path $script:Root "Rules\own\CoreAiRules\managed-settings.json"
			New-Item -ItemType Directory -Path (Split-Path $rulesSource) -Force | Out-Null
			Set-Content -Path $rulesSource -Value "{}"
			$script:Destinations = @(
				New-PlanDestination "skills" "each" $script:Folder @(
					New-PlanItem "skills" "alpha" $script:Alpha (Join-Path $script:Folder "alpha") "/home/you/.claude/skills/alpha"
				) -WSLPath "/home/you/.claude/skills"
				New-PlanDestination "rules" "file" (Join-Path $script:UserDir "managed-settings.json") @(
					New-PlanItem "rules" "CoreAiRules" $rulesSource (Join-Path $script:UserDir "managed-settings.json") "/etc/claude-code/managed-settings.json"
				) -Hooks @("managed-settings") -WSLPath "/etc/claude-code/managed-settings.json"
				New-PlanDestination "agents" "each" (Join-Path $script:UserDir ".claude\agents") @() -WSLPath "/home/you/.claude/agents"
			)
		}

		It "runs one wsl call per destination with items, as the WSL user or as root for managed settings" {
			Deploy-AiArtifacts

			$script:WSLCalls.Count | Should -Be 2
			($script:WSLCalls[0] -join ' ') | Should -BeLike "-d Ubuntu -u you -e sh /mnt/*/winux-ai-artifacts-*.sh"
			($script:WSLCalls[1] -join ' ') | Should -BeLike "-d Ubuntu -u root -e sh *"
			# Only the scripts these calls ran: another run on the machine may have its own in the temp folder.
			foreach ($call in $script:WSLCalls) {
				$wslScript = [string]$call[-1]
				$windowsScript = $wslScript.Substring(5, 1) + ":" + $wslScript.Substring(6).Replace('/', '\')
				Test-Path -LiteralPath $windowsScript | Should -BeFalse
			}
		}

		It "skips the WSL twins when no distribution is installed" {
			Mock Test-WSLDistributionInstalled { $false }

			Deploy-AiArtifacts

			Should -Invoke wsl -Times 0
		}

		It "deploys nothing into WSL under -WhatIf" {
			Deploy-AiArtifacts -WhatIf

			Should -Invoke wsl -Times 0
		}
	}
}
