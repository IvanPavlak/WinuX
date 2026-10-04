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

	It "does nothing when no marketplace is configured" {
		$script:Section = @{}

		Deploy-AiMarketplaces -Command $script:Stub

		Test-Path -Path $script:Settings | Should -BeFalse
		Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "No marketplaces configured*" }
	}
}
