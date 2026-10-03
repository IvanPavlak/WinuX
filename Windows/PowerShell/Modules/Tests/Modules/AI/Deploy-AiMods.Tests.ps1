#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Deploy-AiMods.ps1"
	# The roster walk and the plugin-list merge are dot-sourced so these tests exercise the real
	# flattening and merge rather than whatever the session happens to have loaded.
	. "$FunctionsPath\Get-AiModRoster.ps1"
	. "$FunctionsPath\Resolve-AiModsPluginDirs.ps1"
	# The real Test-Path, captured before any mock exists: invoking the CommandInfo bypasses
	# name resolution, so the pass-through mock below cannot call itself.
	$script:RealTestPath = Get-Command -Name Test-Path -CommandType Cmdlet
}

Describe "Deploy-AiMods" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogDebug { }

		$script:Repo = Join-Path $TestDrive "Repo"
		$script:Root = Join-Path $script:Repo "AI\Mods"
		$script:Harness = Join-Path $TestDrive "home\.claude\mods"
		$script:Settings = Join-Path $TestDrive "home\.claude\settings.json"
		foreach ($stale in @($script:Repo, (Join-Path $TestDrive "home"))) {
			if (Test-Path -Path $stale) { Remove-Item -Path $stale -Recurse -Force }
		}

		foreach ($mod in @("neon\alpha", "neon\bravo", "own\charlie")) {
			$dir = Join-Path $script:Root "$mod\.claude-plugin"
			New-Item -ItemType Directory -Path $dir -Force | Out-Null
			Set-Content -Path (Join-Path $dir "plugin.json") -Value '{"name":"x"}'
		}
		New-Item -ItemType Directory -Path (Join-Path $script:Root "neon\not-a-mod") -Force | Out-Null

		$global:Configuration = [PSCustomObject]@{
			DefaultWSLDistribution = "Ubuntu"
			DefaultWSLUsername     = "you"
		}
		$script:Harnesses = @($script:Harness)
		$script:WSLHarnesses = @()
		Mock Get-RepositoryPath { @{ Repo = $script:Repo } }
		Mock Resolve-AiModsConfig {
			@{
				Root            = $script:Root
				Harnesses       = $script:Harnesses
				WSLHarnesses    = $script:WSLHarnesses
				Sources         = @{}
				SettingsPath    = $script:Settings
				WSLSettingsPath = "/home/you/.claude/settings.json"
			}
		}
		Mock Test-WSLDistributionInstalled { $true }
		Mock Test-AdminPrivileges { }
		# The WSL share is a real path on a machine with WSL; here it is answered by the mock.
		$script:ShareReachable = $true
		# Every other Test-Path goes to the real cmdlet.
		Mock Test-Path { & $script:RealTestPath @PesterBoundParameters }
		Mock Test-Path { $script:ShareReachable } -ParameterFilter { $LiteralPath -like '\\wsl.localhost\*' }
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
		Mock Set-ClaudeSettingsEnv { $true }
		Mock Test-AiModsCli { @{ Installed = $true; Invalid = @() } }
	}

	It "creates the harness directory and links every mod from every source into it" {
		Deploy-AiMods

		Test-Path -Path $script:Harness -PathType Container | Should -BeTrue
		Should -Invoke New-WindowsSymbolicLink -Times 3 -Exactly
		Should -Invoke New-WindowsSymbolicLink -Times 1 -ParameterFilter { $Path -eq (Join-Path $script:Harness "alpha") -and $Target -eq (Join-Path $script:Root "neon\alpha") -and $DisplayName -eq "AiMods.alpha" }
		Should -Invoke New-WindowsSymbolicLink -Times 1 -ParameterFilter { $Path -eq (Join-Path $script:Harness "charlie") -and $Target -eq (Join-Path $script:Root "own\charlie") }
		Should -Invoke New-WindowsSymbolicLink -Times 0 -ParameterFilter { $Path -like "*not-a-mod" }
		Should -Invoke Write-LogError -Times 0
	}

	It "sets CLAUDE_CODE_PLUGIN_DIRS once, to the ';'-joined link paths, in the Windows settings file" {
		Deploy-AiMods

		$expected = @("alpha", "bravo", "charlie" | ForEach-Object { Join-Path $script:Harness $_ }) -join ';'
		Should -Invoke Set-ClaudeSettingsEnv -Times 1 -Exactly
		Should -Invoke Set-ClaudeSettingsEnv -Times 1 -ParameterFilter { $Name -eq "CLAUDE_CODE_PLUGIN_DIRS" -and $Value -eq $expected -and $SettingsPath -eq $script:Settings }
	}

	It "keeps hand-added entries and drops stale harness entries already in the settings file" {
		New-Item -ItemType Directory -Path (Split-Path $script:Settings) -Force | Out-Null
		$existing = "D:\Plugins\other;" + (Join-Path $script:Harness "gone")
		Set-Content -Path $script:Settings -Value (@{ env = @{ CLAUDE_CODE_PLUGIN_DIRS = $existing } } | ConvertTo-Json)

		Deploy-AiMods

		Should -Invoke Set-ClaudeSettingsEnv -Times 1 -ParameterFilter { $Value -like "*\charlie;D:\Plugins\other" -and $Value -notlike "*gone*" }
	}

	It "prunes only dangling links that point inside the mods root, never a sibling folder or a live link" {
		# Junctions are real reparse points that need no admin rights, so the prune walk runs for real.
		New-Item -ItemType Directory -Path $script:Harness -Force | Out-Null
		$goneTarget = Join-Path $script:Root "neon\gone"
		$siblingTarget = Join-Path $script:Repo "AI\ModsBackup\x"
		$elsewhereTarget = Join-Path $TestDrive "other\y"
		foreach ($pair in @(
				@{ Name = "gone"; Target = $goneTarget },
				@{ Name = "sibling"; Target = $siblingTarget },
				@{ Name = "elsewhere"; Target = $elsewhereTarget },
				@{ Name = "not-a-mod"; Target = (Join-Path $script:Root "neon\not-a-mod") })) {
			New-Item -ItemType Directory -Path $pair.Target -Force | Out-Null
			New-Item -ItemType Junction -Path (Join-Path $script:Harness $pair.Name) -Target $pair.Target | Out-Null
		}
		# Three targets vanish, leaving dangling links; only the one under the mods root may go.
		Remove-Item -Path $goneTarget, $siblingTarget, $elsewhereTarget -Recurse -Force

		Deploy-AiMods

		# A listing, not Test-Path: Test-Path answers differently for a dangling link across PowerShell versions.
		$remaining = @(Get-ChildItem -Path $script:Harness -Force | Select-Object -ExpandProperty Name)
		$remaining | Should -Not -Contain "gone"
		$remaining | Should -Contain "sibling"
		$remaining | Should -Contain "elsewhere"
		$remaining | Should -Contain "not-a-mod"
		Should -Invoke Write-LogStep -Times 1 -Exactly -ParameterFilter { $Message -like "*Removed dangling link*" }
		Should -Invoke Write-LogStep -Times 1 -ParameterFilter { $Message -like '*Removed dangling link => `[gone`]*' }
	}

	It "points Claude Code only at the first harness when several are configured" {
		$second = Join-Path $TestDrive "home\other\mods"
		$script:Harnesses = @($script:Harness, $second)

		Deploy-AiMods

		Should -Invoke New-WindowsSymbolicLink -Times 6 -Exactly
		Should -Invoke Set-ClaudeSettingsEnv -Times 1 -Exactly
		Should -Invoke Set-ClaudeSettingsEnv -Times 1 -ParameterFilter { $Value -notlike "*other\mods*" }
	}

	It "keeps the first source's copy when two sources ship the same mod name" {
		$dup = Join-Path $script:Root "own\alpha\.claude-plugin"
		New-Item -ItemType Directory -Path $dup -Force | Out-Null
		Set-Content -Path (Join-Path $dup "plugin.json") -Value '{"name":"alpha"}'

		Deploy-AiMods

		Should -Invoke New-WindowsSymbolicLink -Times 1 -Exactly -ParameterFilter { $Path -eq (Join-Path $script:Harness "alpha") }
		Should -Invoke New-WindowsSymbolicLink -Times 1 -ParameterFilter { $Path -eq (Join-Path $script:Harness "alpha") -and $Target -eq (Join-Path $script:Root "neon\alpha") }
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*Duplicate mod*alpha*" }
	}

	It "warns and does nothing - no links, no settings - when the root does not exist or holds no mods" {
		Remove-Item -Path $script:Root -Recurse -Force
		Deploy-AiMods
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*does not exist*" }

		New-Item -ItemType Directory -Path (Join-Path $script:Root "empty") -Force | Out-Null
		Deploy-AiMods
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*No mods found*" }

		Should -Invoke New-WindowsSymbolicLink -Times 0
		Should -Invoke Set-ClaudeSettingsEnv -Times 0
		Should -Invoke Test-AiModsCli -Times 0
	}

	It "skips a harness path occupied by a file, and then has no settings to update" {
		New-Item -ItemType Directory -Path (Split-Path $script:Harness) -Force | Out-Null
		Set-Content -Path $script:Harness -Value "not a directory"

		Deploy-AiMods

		Should -Invoke New-WindowsSymbolicLink -Times 0
		Should -Invoke Set-ClaudeSettingsEnv -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*a file sits at that path*" }
	}

	It "links mods into WSL with one script per harness and updates the WSL settings through the share" {
		$script:WSLHarnesses = @("/home/you/.claude/mods")
		$driveLetter = $script:Root.Substring(0, 1).ToLower()
		$wslAlpha = "/mnt/$driveLetter" + (Join-Path $script:Root "neon\alpha").Substring(2).Replace('\', '/')

		Deploy-AiMods

		Should -Invoke wsl -Times 1 -Exactly -ParameterFilter { "$args" -like "-d Ubuntu -u you -e sh /mnt/*/winux-ai-mods-*.sh" }
		$script:WSLScripts.Count | Should -Be 1
		$script:WSLScripts[0] | Should -Match "(?m)^set -e$"
		$script:WSLScripts[0] | Should -Match "(?m)^h='/home/you/.claude/mods'$"
		$script:WSLScripts[0] | Should -Match ([regex]::Escape("ln -sfn '$wslAlpha' `"`$h/alpha`""))
		Get-ChildItem -Path ([IO.Path]::GetTempPath()) -Filter "winux-ai-mods-*.sh" | Should -BeNullOrEmpty

		Should -Invoke Set-ClaudeSettingsEnv -Times 2 -Exactly
		Should -Invoke Set-ClaudeSettingsEnv -Times 1 -ParameterFilter {
			$SettingsPath -eq "\\wsl.localhost\Ubuntu\home\you\.claude\settings.json" -and
			$Value -eq "/home/you/.claude/mods/alpha:/home/you/.claude/mods/bravo:/home/you/.claude/mods/charlie"
		}
	}

	It "warns and skips the WSL settings when the share is unreachable, keeping the links" {
		$script:WSLHarnesses = @("/home/you/.claude/mods")
		$script:ShareReachable = $false

		Deploy-AiMods

		Should -Invoke wsl -Times 1 -Exactly
		Should -Invoke Set-ClaudeSettingsEnv -Times 1 -Exactly -ParameterFilter { $SettingsPath -eq $script:Settings }
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*not reachable*" }
	}

	It "skips WSL when no distribution is installed" {
		$script:WSLHarnesses = @("/home/you/.claude/mods")
		Mock Test-WSLDistributionInstalled { $false }

		Deploy-AiMods

		Should -Invoke wsl -Times 0
		Should -Invoke Set-ClaudeSettingsEnv -Times 1 -Exactly
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*WSL distribution not installed*" }
	}

	It "reports a failed WSL link command and does not touch the WSL settings" {
		$script:WSLHarnesses = @("/home/you/.claude/mods")
		Mock wsl { $global:LASTEXITCODE = 1 }

		Deploy-AiMods

		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -like "*Failed to link mods into WSL*" }
		Should -Invoke Set-ClaudeSettingsEnv -Times 0 -ParameterFilter { $SettingsPath -like '\\wsl.localhost\*' }
	}

	It "still deploys links and settings when the CLI is missing, and warns that mods cannot be used yet" {
		Mock Test-AiModsCli { @{ Installed = $false; Invalid = @() } }

		Deploy-AiMods

		Should -Invoke New-WindowsSymbolicLink -Times 3 -Exactly
		Should -Invoke Set-ClaudeSettingsEnv -Times 1 -Exactly
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like "*not found on PATH*cannot be used until*" }
	}

	It "validates the Windows links and warns naming every mod the CLI rejects" {
		Mock Test-AiModsCli { @{ Installed = $true; Invalid = @((Join-Path $script:Harness "bravo")) } }

		Deploy-AiMods

		Should -Invoke Test-AiModsCli -Times 1 -ParameterFilter { @($ModPath).Count -eq 3 -and $ModPath[0] -eq (Join-Path $script:Harness "alpha") }
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -like '*validate failed for `[bravo`]*cannot be used until*' }
		Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -eq "AI mods deployed!" }
	}

	It "requires administrator privileges before touching anything" {
		Deploy-AiMods

		Should -Invoke Test-AdminPrivileges -Times 1 -Exactly
	}
}
