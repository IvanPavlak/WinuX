#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Deploy-AiMarketplaces.ps1"
	# The settings writer is dot-sourced so these tests exercise the real file edit.
	. "$FunctionsPath\Set-ClaudeSettingsKey.ps1"
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

		# A stand-in CLI: records every call; `plugin list --json` answers what the test set.
		$script:Log = Join-Path $TestDrive "calls.log"
		if (Test-Path -Path $script:Log) { Remove-Item -Path $script:Log -Force }
		$env:WINUX_TEST_PLUGIN_LIST = "[]"
		$script:Stub = Join-Path $TestDrive "claude-stub.ps1"
		Set-Content -Path $script:Stub -Value @(
			"Add-Content -Path '$script:Log' -Value (`$args -join ' ')",
			"if (`$args[1] -eq 'list') { Write-Output `$env:WINUX_TEST_PLUGIN_LIST; exit 0 }",
			"if (`$args[2] -like '*broken*') { exit 1 }",
			"exit 0"
		)
	}

	AfterEach {
		Remove-Item -Path Env:\WINUX_TEST_PLUGIN_LIST -ErrorAction SilentlyContinue
	}

	It "registers the marketplace in the user settings" {
		Deploy-AiMarketplaces -Command $script:Stub

		$document = Get-Content -Path $script:Settings -Raw | ConvertFrom-Json
		$document.extraKnownMarketplaces.'my-marketplace'.source.source | Should -Be "github"
		$document.extraKnownMarketplaces.'my-marketplace'.source.repo | Should -Be "MyOrg/MyMarketplace"
	}

	It "seeds the plugin options one child key at a time, keeping what the user set" {
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:Settings) -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{"pluginConfigs":{"my-plugin":{"options":{"glyph":"x"},"other":1}},"env":{"A":"b"}}'

		Deploy-AiMarketplaces -Command $script:Stub

		$document = Get-Content -Path $script:Settings -Raw | ConvertFrom-Json
		$document.pluginConfigs.'my-plugin'.options.theme | Should -Be "dark"
		$document.pluginConfigs.'my-plugin'.options.PSObject.Properties['glyph'] | Should -BeNullOrEmpty -Because "the repository's `options` replaces the whole `options` object"
		$document.pluginConfigs.'my-plugin'.other | Should -Be 1 -Because "a sibling the repository does not name survives"
		$document.env.A | Should -Be "b"
	}

	It "installs a plugin the CLI does not list yet" {
		Deploy-AiMarketplaces -Command $script:Stub

		@(Get-Content -Path $script:Log) | Should -Be @("plugin list --json", "plugin install my-plugin@my-marketplace")
		Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq "Installed plugin [my-plugin@my-marketplace]" }
	}

	It "leaves an installed plugin alone" {
		$env:WINUX_TEST_PLUGIN_LIST = '[{"id":"my-plugin@my-marketplace","version":"1.0.0"}]'

		Deploy-AiMarketplaces -Command $script:Stub

		@(Get-Content -Path $script:Log) | Should -Be @("plugin list --json")
		Should -Invoke Write-LogStep -ParameterFilter { $Message -eq "Plugin [my-plugin@my-marketplace] already installed" }
	}

	It "reports a failed install as an error and carries on" {
		$script:Section.Marketplaces.'my-marketplace'.Plugins = @("broken", "my-plugin")

		Deploy-AiMarketplaces -Command $script:Stub

		Should -Invoke Write-LogError -ParameterFilter { $Message -like "claude plugin install [[]broken@my-marketplace] failed*" }
		Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq "Installed plugin [my-plugin@my-marketplace]" }
	}

	It "deploys the settings and only warns when the CLI is missing" {
		Deploy-AiMarketplaces -Command "winux-no-such-command-$([guid]::NewGuid())"

		Test-Path -Path $script:Settings | Should -BeTrue
		Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "Claude Code CLI (claude) not found on PATH*my-plugin@my-marketplace*" }
	}

	It "skips a marketplace without a valid repository" {
		$script:Section.Marketplaces.bad = @{ Repository = "not a repo" }

		Deploy-AiMarketplaces -Command $script:Stub

		$document = Get-Content -Path $script:Settings -Raw | ConvertFrom-Json
		$document.extraKnownMarketplaces.PSObject.Properties['bad'] | Should -BeNullOrEmpty
		Should -Invoke Write-LogError -ParameterFilter { $Message -like "Marketplace [[]bad] has no valid Repository*" }
	}

	It "does nothing when no marketplace is configured" {
		$script:Section = @{}

		Deploy-AiMarketplaces -Command $script:Stub

		Test-Path -Path $script:Settings | Should -BeFalse
		Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "No marketplaces configured*" }
	}
}
