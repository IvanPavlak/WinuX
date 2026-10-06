#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Deploy-AiMarketplaces.ps1"
	# The settings writers are dot-sourced so these tests exercise the real file edits.
	. "$FunctionsPath\Set-ClaudeSettingsKey.ps1"
	. "$FunctionsPath\Set-ClaudeSettingsEnv.ps1"
}

Describe "Deploy-AiMarketplaces" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogDebug { }

		$script:Settings = Join-Path $TestDrive "home\.claude\settings.json"
		if (Test-Path -Path (Join-Path $TestDrive "home")) { Remove-Item -Path (Join-Path $TestDrive "home") -Recurse -Force }

		$script:Section = @{
			Marketplaces  = @{
				"my-marketplace" = @{
					Repository = "MyOrg/MyMarketplace"
					Plugins    = @("my-plugin")
					Env        = @{ CLAUDE_CODE_ENABLE_FUNCTION_HOOKS = "1" }
				}
			}
			PluginConfigs = @{
				"my-plugin" = @{
					options = @{ theme = "dark"; pulse = $true }
				}
			}
		}
		Mock Get-ConfigSetting {
			switch ($Path) {
				'AiMarketplaces' { $script:Section }
				'DefaultWSLDistribution' { "" }
				default { $null }
			}
		}
		Mock Resolve-AiModsConfig { @{ SettingsPath = $script:Settings; WSLSettingsPath = "" } }
		Mock Test-WSLDistributionInstalled { $false }

		# A stand-in CLI: records every call; the two `list --json` calls answer what the test set.
		$script:Log = Join-Path $TestDrive "calls.log"
		if (Test-Path -Path $script:Log) { Remove-Item -Path $script:Log -Force }
		$env:WINUX_TEST_MARKETPLACE_LIST = "[]"
		$env:WINUX_TEST_PLUGIN_LIST = "[]"
		$script:Stub = Join-Path $TestDrive "claude-stub.ps1"
		Set-Content -Path $script:Stub -Value @(
			"Add-Content -Path '$script:Log' -Value (`$args -join ' ')",
			"if (`$args[1] -eq 'marketplace' -and `$args[2] -eq 'list') { Write-Output `$env:WINUX_TEST_MARKETPLACE_LIST; exit 0 }",
			"if (`$args[1] -eq 'list') { Write-Output `$env:WINUX_TEST_PLUGIN_LIST; exit 0 }",
			"if ((`$args -join ' ') -like '*broken*') { exit 1 }",
			"exit 0"
		)
	}

	AfterEach {
		Remove-Item -Path Env:\WINUX_TEST_MARKETPLACE_LIST -ErrorAction SilentlyContinue
		Remove-Item -Path Env:\WINUX_TEST_PLUGIN_LIST -ErrorAction SilentlyContinue
	}

	It "registers the marketplace in the user settings" {
		Deploy-AiMarketplaces -Command $script:Stub

		$document = Get-Content -Path $script:Settings -Raw | ConvertFrom-Json
		$document.extraKnownMarketplaces.'my-marketplace'.source.source | Should -Be "github"
		$document.extraKnownMarketplaces.'my-marketplace'.source.repo | Should -Be "MyOrg/MyMarketplace"
	}

	It "writes the variables the marketplace's plugins need into the env block, keeping the other variables" {
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:Settings) -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{"env":{"CLAUDE_CODE_PLUGIN_DIRS":"C:\\mods\\x"},"tui":"fullscreen"}'

		Deploy-AiMarketplaces -Command $script:Stub

		$document = Get-Content -Path $script:Settings -Raw | ConvertFrom-Json
		$document.env.CLAUDE_CODE_ENABLE_FUNCTION_HOOKS | Should -Be "1"
		$document.env.CLAUDE_CODE_PLUGIN_DIRS | Should -Be "C:\mods\x" -Because "the variable Deploy-AiMods writes is a sibling, not ours"
		$document.tui | Should -Be "fullscreen"
	}

	It "writes a variable's value as a string and the last marketplace by name wins a clash" {
		$script:Section.Marketplaces.'my-marketplace'.Env = @{ WINUX_TEST_SHARED = 1 }
		$script:Section.Marketplaces.'other-marketplace' = @{ Repository = "MyOrg/Other"; Env = @{ WINUX_TEST_SHARED = "two" } }

		Deploy-AiMarketplaces -Command $script:Stub

		$document = Get-Content -Path $script:Settings -Raw | ConvertFrom-Json
		$document.env.WINUX_TEST_SHARED | Should -BeOfType [string]
		$document.env.WINUX_TEST_SHARED | Should -Be "two"
	}

	It "skips an invalid variable name and an Env that is not a hashtable, writing the rest" {
		$script:Section.Marketplaces.'my-marketplace'.Env = @{ "NOT VALID" = "x"; CLAUDE_CODE_ENABLE_FUNCTION_HOOKS = "1" }
		$script:Section.Marketplaces.'other-marketplace' = @{ Repository = "MyOrg/Other"; Env = "CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1" }

		Deploy-AiMarketplaces -Command $script:Stub

		$document = Get-Content -Path $script:Settings -Raw | ConvertFrom-Json
		$document.env.CLAUDE_CODE_ENABLE_FUNCTION_HOOKS | Should -Be "1"
		$document.env.PSObject.Properties['NOT VALID'] | Should -BeNullOrEmpty
		$document.extraKnownMarketplaces.'other-marketplace'.source.repo | Should -Be "MyOrg/Other" -Because "a bad Env does not skip the marketplace itself"
		Should -Invoke Write-LogError -ParameterFilter { $Message -like "Marketplace [[]my-marketplace] names an invalid environment variable [[]NOT VALID]*" }
		Should -Invoke Write-LogError -ParameterFilter { $Message -like "Marketplace [[]other-marketplace] has an Env that is not a hashtable*" }
	}

	It "seeds the options under the installed plugin's id, one child key at a time, keeping what the user set" {
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:Settings) -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{"pluginConfigs":{"my-plugin@my-marketplace":{"options":{"glyph":"x"},"other":1}},"env":{"A":"b"}}'

		Deploy-AiMarketplaces -Command $script:Stub

		$document = Get-Content -Path $script:Settings -Raw | ConvertFrom-Json
		$entry = $document.pluginConfigs.'my-plugin@my-marketplace'
		$entry.options.theme | Should -Be "dark"
		$entry.options.PSObject.Properties['glyph'] | Should -BeNullOrEmpty -Because "the repository's `options` replaces the whole `options` object"
		$entry.other | Should -Be 1 -Because "a sibling the repository does not name survives"
		$document.pluginConfigs.PSObject.Properties['my-plugin'] | Should -BeNullOrEmpty -Because "a plugin a marketplace lists is keyed <plugin>@<marketplace>"
		$document.env.A | Should -Be "b"
	}

	It "writes options for a plugin no marketplace lists under the name as given" {
		$script:Section.PluginConfigs = @{ "folder-plugin" = @{ options = @{ theme = "light" } } }

		Deploy-AiMarketplaces -Command $script:Stub

		(Get-Content -Path $script:Settings -Raw | ConvertFrom-Json).pluginConfigs.'folder-plugin'.options.theme | Should -Be "light"
	}

	It "adds the marketplace through the CLI and installs a plugin it does not list yet" {
		Deploy-AiMarketplaces -Command $script:Stub

		@(Get-Content -Path $script:Log) | Should -Be @(
			"plugin marketplace list --json",
			"plugin marketplace add MyOrg/MyMarketplace",
			"plugin list --json",
			"plugin install my-plugin@my-marketplace"
		)
		Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq "Added marketplace [my-marketplace] (MyOrg/MyMarketplace)" }
		Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq "Installed plugin [my-plugin@my-marketplace]" }
	}

	It "leaves a known marketplace and an installed plugin alone" {
		$env:WINUX_TEST_MARKETPLACE_LIST = '[{"name":"my-marketplace","source":"github","repo":"MyOrg/MyMarketplace"}]'
		$env:WINUX_TEST_PLUGIN_LIST = '[{"id":"my-plugin@my-marketplace","version":"1.0.0"}]'

		Deploy-AiMarketplaces -Command $script:Stub

		@(Get-Content -Path $script:Log) | Should -Be @("plugin marketplace list --json", "plugin list --json")
		Should -Invoke Write-LogStep -ParameterFilter { $Message -eq "Marketplace [my-marketplace] already added" }
		Should -Invoke Write-LogStep -ParameterFilter { $Message -eq "Plugin [my-plugin@my-marketplace] already installed" }
	}

	It "reports a failed install as an error and carries on" {
		$script:Section.Marketplaces.'my-marketplace'.Plugins = @("broken", "my-plugin")

		Deploy-AiMarketplaces -Command $script:Stub

		Should -Invoke Write-LogError -ParameterFilter { $Message -like "claude plugin install [[]broken@my-marketplace] failed*" }
		Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq "Installed plugin [my-plugin@my-marketplace]" }
	}

	It "reports a failed marketplace add as an error and still tries the install" {
		$script:Section.Marketplaces.'my-marketplace'.Repository = "MyOrg/broken-marketplace"

		Deploy-AiMarketplaces -Command $script:Stub

		Should -Invoke Write-LogError -ParameterFilter { $Message -like "claude plugin marketplace add [[]MyOrg/broken-marketplace] failed*" }
		@(Get-Content -Path $script:Log) | Should -Contain "plugin install my-plugin@my-marketplace"
	}

	It "deploys the settings and only warns when the CLI is missing" {
		Deploy-AiMarketplaces -Command "winux-no-such-command-$([guid]::NewGuid())"

		Test-Path -Path $script:Settings | Should -BeTrue
		Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "Claude Code CLI (claude) not found on PATH*" }
	}

	It "skips a marketplace without a valid repository" {
		$script:Section.Marketplaces.bad = @{ Repository = "not a repo" }

		Deploy-AiMarketplaces -Command $script:Stub

		$document = Get-Content -Path $script:Settings -Raw | ConvertFrom-Json
		$document.extraKnownMarketplaces.PSObject.Properties['bad'] | Should -BeNullOrEmpty
		Should -Invoke Write-LogError -ParameterFilter { $Message -like "Marketplace [[]bad] has no valid Repository*" }
	}

	It "warns when a CLAUDE_CODE_PLUGIN_DIRS folder holds a plugin a marketplace installs, and leaves the entry" {
		$clone = Join-Path $TestDrive "clone"
		New-Item -ItemType Directory -Path (Join-Path $clone ".claude-plugin") -Force | Out-Null
		Set-Content -Path (Join-Path $clone ".claude-plugin\plugin.json") -Value '{"name":"my-plugin"}'
		$other = Join-Path $TestDrive "other-mod"
		New-Item -ItemType Directory -Path (Join-Path $other ".claude-plugin") -Force | Out-Null
		Set-Content -Path (Join-Path $other ".claude-plugin\plugin.json") -Value '{"name":"other-mod"}'
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:Settings) -Force | Out-Null
		@{ env = @{ CLAUDE_CODE_PLUGIN_DIRS = "$other;$clone" } } | ConvertTo-Json | Set-Content -Path $script:Settings

		Deploy-AiMarketplaces -Command $script:Stub

		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "Plugin [[]my-plugin@my-marketplace] is installed from its marketplace and also loaded from [[]$clone]*" }
		Should -Invoke Write-LogWarning -Times 0 -Exactly -ParameterFilter { $Message -like "*other-mod*" }
		(Get-Content -Path $script:Settings -Raw | ConvertFrom-Json).env.CLAUDE_CODE_PLUGIN_DIRS | Should -Be "$other;$clone" -Because "the entry is the user's and only reported"
	}

	Context "inside WSL" {
		BeforeEach {
			Mock Resolve-AiModsConfig { @{ SettingsPath = $script:Settings; WSLSettingsPath = "/home/u/.claude/settings.json" } }
			Mock Test-WSLDistributionInstalled { $true }
			Mock Get-ConfigSetting {
				switch ($Path) {
					'AiMarketplaces' { $script:Section }
					'DefaultWSLDistribution' { "WinuXTestDistro-$([guid]::Empty)" }
					'DefaultWSLUsername' { "u" }
					default { $null }
				}
			}
			# A stand-in wsl.exe: `command -v claude` answers WINUX_TEST_WSL_CLAUDE; a claude call
			# (everything after the `claude` that names $0) is recorded and answered like the CLI stub.
			$script:WslLog = Join-Path $TestDrive "wsl-calls.log"
			if (Test-Path -Path $script:WslLog) { Remove-Item -Path $script:WslLog -Force }
			$env:WINUX_TEST_WSL_CLAUDE = "/home/u/.local/bin/claude"
			$script:WslStub = Join-Path $TestDrive "wsl-stub.ps1"
			Set-Content -Path $script:WslStub -Value @(
				"if ((`$args -join ' ') -like '*command -v claude*') { if (`$env:WINUX_TEST_WSL_CLAUDE) { Write-Output `$env:WINUX_TEST_WSL_CLAUDE; exit 0 }; exit 1 }",
				"`$rest = `$args[([array]::IndexOf(`$args, 'claude') + 1)..(`$args.Count - 1)]",
				"Add-Content -Path '$script:WslLog' -Value (`$rest -join ' ')",
				"if (`$rest[1] -eq 'marketplace' -and `$rest[2] -eq 'list') { Write-Output '[]'; exit 0 }",
				"if (`$rest[1] -eq 'list') { Write-Output '[]'; exit 0 }",
				"exit 0"
			)
		}

		AfterEach {
			Remove-Item -Path Env:\WINUX_TEST_WSL_CLAUDE -ErrorAction SilentlyContinue
		}

		It "adds the marketplace and installs the plugin through the CLI inside WSL" {
			Deploy-AiMarketplaces -Command $script:Stub -WslCommand $script:WslStub

			@(Get-Content -Path $script:WslLog) | Should -Be @(
				"plugin marketplace list --json",
				"plugin marketplace add MyOrg/MyMarketplace",
				"plugin list --json",
				"plugin install my-plugin@my-marketplace"
			)
			Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq "[WSL] Installed plugin [my-plugin@my-marketplace]" }
			@(Get-Content -Path $script:Log) | Should -Contain "plugin install my-plugin@my-marketplace" -Because "the Windows CLI is still deployed first"
		}

		It "treats the Windows CLI reached through interop as missing inside WSL" {
			$env:WINUX_TEST_WSL_CLAUDE = "/mnt/c/Users/u/AppData/Roaming/npm/claude"

			Deploy-AiMarketplaces -Command $script:Stub -WslCommand $script:WslStub

			Test-Path -Path $script:WslLog | Should -BeFalse
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "WSL [[]*] resolves claude to the Windows CLI [[]/mnt/c/*" }
		}

		It "only warns when WSL has no Claude Code CLI" {
			$env:WINUX_TEST_WSL_CLAUDE = ""

			Deploy-AiMarketplaces -Command $script:Stub -WslCommand $script:WslStub

			Test-Path -Path $script:WslLog | Should -BeFalse
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "Claude Code CLI (claude) not found inside WSL*" }
			Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq "AI marketplaces deployed!" }
		}
	}

	It "does nothing when no marketplace is configured" {
		$script:Section = @{}

		Deploy-AiMarketplaces -Command $script:Stub

		Test-Path -Path $script:Settings | Should -BeFalse
		Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "No marketplaces configured*" }
	}
}
