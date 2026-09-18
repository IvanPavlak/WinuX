#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Deploy-AiSkills.ps1"
	# The roster walk it shares with List-Skills; dot-sourced so these tests exercise the real
	# flattening rather than whatever the session happens to have loaded.
	. "$FunctionsPath\Get-AiSkillRoster.ps1"
}

Describe "Deploy-AiSkills" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }

		$script:Repo = Join-Path $TestDrive "Repo"
		$script:Root = Join-Path $script:Repo "AI\Skills"
		$script:Harness = Join-Path $TestDrive "home\.claude\skills"
		foreach ($stale in @($script:Repo, (Join-Path $TestDrive "home"))) {
			if (Test-Path -Path $stale) { Remove-Item -Path $stale -Recurse -Force }
		}

		foreach ($skill in @("mattpocock\alpha", "mattpocock\bravo", "own\charlie")) {
			$dir = Join-Path $script:Root $skill
			New-Item -ItemType Directory -Path $dir -Force | Out-Null
			Set-Content -Path (Join-Path $dir "SKILL.md") -Value "skill"
		}
		New-Item -ItemType Directory -Path (Join-Path $script:Root "mattpocock\not-a-skill") -Force | Out-Null

		$global:Configuration = [PSCustomObject]@{
			DefaultWSLDistribution = "Ubuntu"
			DefaultWSLUsername     = "you"
		}
		$script:WSLHarnesses = @()
		Mock Get-RepositoryPath { @{ Repo = $script:Repo } }
		Mock Resolve-AiSkillsConfig { @{ Root = $script:Root; Harnesses = @($script:Harness); WSLHarnesses = $script:WSLHarnesses; Sources = @{} } }
		Mock Test-WSLDistributionInstalled { $true }
		Mock Test-AdminPrivileges { }
		# The WSL script file is deleted right after the call, so the mock captures its content.
		$script:WSLScripts = @()
		Mock wsl {
			$scriptArgument = [string]$args[-1]
			$windowsPath = $scriptArgument -replace '^/mnt/(\w)/', '$1:/'
			$script:WSLScripts += Get-Content -Path $windowsPath -Raw
			$global:LASTEXITCODE = 0
		}
		# Links are the unit under test's side effect; the engine primitive is mocked so the
		# tests need neither admin rights nor Developer Mode.
		Mock New-WindowsSymbolicLink { }
	}

	It "creates the harness directory and links every skill from every source into it" {
		Deploy-AiSkills

		Test-Path -Path $script:Harness -PathType Container | Should -BeTrue
		Should -Invoke New-WindowsSymbolicLink -Times 3 -Exactly
		Should -Invoke New-WindowsSymbolicLink -Times 1 -ParameterFilter { $Path -eq (Join-Path $script:Harness "alpha") -and $Target -eq (Join-Path $script:Root "mattpocock\alpha") }
		Should -Invoke New-WindowsSymbolicLink -Times 1 -ParameterFilter { $Path -eq (Join-Path $script:Harness "charlie") -and $Target -eq (Join-Path $script:Root "own\charlie") }
		Should -Invoke New-WindowsSymbolicLink -Times 0 -ParameterFilter { $Path -like "*not-a-skill" }
		Should -Invoke Write-LogError -Times 0
	}

	It "keeps the first source's copy when two sources ship the same skill name" {
		$dup = Join-Path $script:Root "own\alpha"
		New-Item -ItemType Directory -Path $dup -Force | Out-Null
		Set-Content -Path (Join-Path $dup "SKILL.md") -Value "dup"

		Deploy-AiSkills

		Should -Invoke New-WindowsSymbolicLink -Times 1 -Exactly -ParameterFilter { $Path -eq (Join-Path $script:Harness "alpha") }
		Should -Invoke New-WindowsSymbolicLink -Times 1 -ParameterFilter { $Path -eq (Join-Path $script:Harness "alpha") -and $Target -eq (Join-Path $script:Root "mattpocock\alpha") }
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*Duplicate skill*alpha*" }
	}

	It "warns and does nothing when the skills root does not exist or holds no skills" {
		Remove-Item -Path $script:Root -Recurse -Force
		Deploy-AiSkills
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*does not exist*" }

		New-Item -ItemType Directory -Path (Join-Path $script:Root "empty") -Force | Out-Null
		Deploy-AiSkills
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*No skills found*" }

		Should -Invoke New-WindowsSymbolicLink -Times 0
	}

	It "skips a harness path occupied by a file" {
		New-Item -ItemType Directory -Path (Split-Path $script:Harness) -Force | Out-Null
		Set-Content -Path $script:Harness -Value "not a directory"

		Deploy-AiSkills

		Should -Invoke New-WindowsSymbolicLink -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*a file sits at that path*" }
	}

	It "links skills into every WSL harness with one script each, executed directly as the WSL user" {
		$script:WSLHarnesses = @("/home/you/.claude/skills", "/home/you/.agents/skills")
		$driveLetter = $script:Root.Substring(0, 1).ToLower()
		$wslAlpha = "/mnt/$driveLetter" + (Join-Path $script:Root "mattpocock\alpha").Substring(2).Replace('\', '/')

		Deploy-AiSkills

		Should -Invoke wsl -Times 2 -Exactly
		# -e bypasses the login shell, so the script file is executed as one unit.
		Should -Invoke wsl -Times 2 -Exactly -ParameterFilter { "$args" -like "-d Ubuntu -u you -e sh /mnt/*/winux-ai-skills-*.sh" }
		$script:WSLScripts.Count | Should -Be 2
		$script:WSLScripts[0] | Should -Match "(?m)^set -e$"
		$script:WSLScripts[0] | Should -Match "(?m)^h='/home/you/.claude/skills'$"
		$script:WSLScripts[0] | Should -Match "(?m)^mkdir -p `"\`$h`"$"
		$script:WSLScripts[0] | Should -Match ([regex]::Escape("ln -sfn '$wslAlpha' `"`$h/alpha`""))
		$script:WSLScripts[1] | Should -Match "(?m)^h='/home/you/.agents/skills'$"
		# The temp script is cleaned up after each call.
		Get-ChildItem -Path ([IO.Path]::GetTempPath()) -Filter "winux-ai-skills-*.sh" | Should -BeNullOrEmpty
	}

	It "requires administrator privileges before touching anything" {
		Deploy-AiSkills

		Should -Invoke Test-AdminPrivileges -Times 1 -Exactly
	}

	It "skips WSL when no distribution is installed" {
		$script:WSLHarnesses = @("/home/you/.claude/skills")
		Mock Test-WSLDistributionInstalled { $false }

		Deploy-AiSkills

		Should -Invoke wsl -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*WSL distribution not installed*" }
	}

	It "reports a failed WSL link command" {
		$script:WSLHarnesses = @("/home/you/.claude/skills")
		Mock wsl { $global:LASTEXITCODE = 1 }

		Deploy-AiSkills

		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -like "*Failed to link skills into WSL*" }
	}
}
