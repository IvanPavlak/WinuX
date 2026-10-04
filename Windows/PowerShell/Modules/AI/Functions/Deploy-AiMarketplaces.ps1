function Deploy-AiMarketplaces {
	<#
	.SYNOPSIS
		Registers the configured Claude Code plugin marketplaces, installs their plugins through the Claude Code CLI, and seeds the plugins' options in the user settings.

	.DESCRIPTION
		Claude Code plugins published through a marketplace (a repository carrying
		.claude-plugin\marketplace.json) are installed with `claude plugin marketplace add` and
		`claude plugin install <plugin>@<marketplace>`, and the engine then keeps them updated.
		That is a per-machine, per-user action, so this function makes it part of Bootstrap:

		1. Marketplaces in the settings: for every entry of AiMarketplaces.Marketplaces it sets
		   `extraKnownMarketplaces.<name>` of the user's ~\.claude\settings.json to the GitHub
		   source of the repository (through Set-ClaudeSettingsKey, every other setting kept),
		   so Claude Code knows the marketplace on every start.
		2. Options: every entry of AiMarketplaces.PluginConfigs is written beneath the plugin's
		   `pluginConfigs` entry, one child key at a time, so an option the user set through
		   /plugin and the repository does not name survives while the repository's values win
		   for the keys it names. A plugin a configured marketplace lists is keyed the way an
		   installed plugin is, `pluginConfigs.<plugin>@<marketplace>`; any other name is
		   written as given (`pluginConfigs.<name>`, the shape of a folder-loaded plugin).
		3. The CLI: when the Claude Code CLI is on PATH, every configured marketplace that
		   `claude plugin marketplace list --json` does not show is added with
		   `claude plugin marketplace add <owner/name>` (the settings key alone takes effect
		   only on the engine's next start), and every plugin an entry's Plugins lists is
		   installed as <plugin>@<marketplace> unless `claude plugin list --json` already
		   shows it. A missing CLI only produces a warning - the settings are deployed
		   regardless, so installing the CLI and running Bootstrap again finishes the job.
		   Already installed plugins are left to `claude plugin update`.

		Inside WSL the same marketplaces and options are written to the WSL user's settings file
		(/home/<DefaultWSLUsername>/.claude/settings.json through the \\wsl.localhost\<distro>
		share) when a WSL distribution and user are configured; the CLI steps have to be run
		inside WSL, which a warning says.

		Mods loaded from a folder (Deploy-AiMods) and plugins installed from a marketplace are
		two ways to load the same plugin: give each plugin one of them, not both.

		Idempotent: a marketplace already known and a plugin already installed are reported and
		left alone. Called by Bootstrap when the opt-in BootstrapConfig.Steps.AiMarketplaces
		toggle is enabled (OFF by default); the base configuration names no marketplaces, so a
		vanilla run deploys nothing.

	.PARAMETER Command
		The Claude Code CLI to call. Defaults to `claude`; tests pass a stub script.

	.EXAMPLE
		Deploy-AiMarketplaces
		Registers every configured marketplace, seeds the options and installs the plugins.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string]$Command = 'claude'
	)

	Write-LogTitle "Deploying AI Marketplaces"

	$section = Get-ConfigSetting -Path 'AiMarketplaces'
	if ($section -isnot [hashtable]) { $section = @{} }
	$marketplaces = if ($section.Marketplaces -is [hashtable]) { $section.Marketplaces } else { @{} }
	$pluginConfigs = if ($section.PluginConfigs -is [hashtable]) { $section.PluginConfigs } else { @{} }

	if ($marketplaces.Count -eq 0) {
		Write-LogWarning "No marketplaces configured under AiMarketplaces.Marketplaces - nothing to deploy!"
		return
	}

	# The Windows and WSL settings files come from the same resolver the mods use.
	$paths = Resolve-AiModsConfig
	$targets = @(@{ Label = "Windows"; Path = $paths.SettingsPath })
	if ($paths.WSLSettingsPath) {
		if (Test-WSLDistributionInstalled) {
			$distro = [string](Get-ConfigSetting -Path 'DefaultWSLDistribution')
			$sharePath = "\\wsl.localhost\$distro" + $paths.WSLSettingsPath.Replace('/', '\')
			if (Test-Path -LiteralPath (Split-Path -Parent (Split-Path -Parent $sharePath))) {
				$targets += @{ Label = "WSL"; Path = $sharePath }
			}
			else {
				Write-LogWarning "WSL share for [$distro] unreachable - the WSL Claude Code settings were not updated!"
			}
		}
	}

	# Validated once: a marketplace entry is a GitHub repository and an optional plugin list.
	$valid = [ordered]@{}
	foreach ($name in ($marketplaces.Keys | Sort-Object)) {
		$entry = $marketplaces[$name]
		$repository = if ($entry -is [hashtable]) { [string]$entry.Repository } else { "" }
		if ($repository -notmatch '^[\w.-]+/[\w.-]+$') {
			Write-LogError "Marketplace [$name] has no valid Repository (owner/name) - skipped!"
			continue
		}
		$plugins = if ($entry.Plugins) { @($entry.Plugins | ForEach-Object { [string]$_ } | Where-Object { $_ }) } else { @() }
		$valid[$name] = @{ Repository = $repository; Plugins = $plugins }
	}

	# A plugin a configured marketplace lists is keyed <plugin>@<marketplace> in pluginConfigs,
	# as the engine keys an installed plugin; any other name is written as given.
	$pluginKey = {
		param($plugin)
		foreach ($name in $valid.Keys) {
			if ($valid[$name].Plugins -contains $plugin) { return "$plugin@$name" }
		}
		return $plugin
	}

	foreach ($target in $targets) {
		Write-LogStep "[$($target.Label)] $($target.Path)"
		foreach ($name in $valid.Keys) {
			$source = @{ source = @{ source = "github"; repo = $valid[$name].Repository } }
			if (Set-ClaudeSettingsKey -Path "extraKnownMarketplaces.$name" -Value $source -SettingsPath $target.Path) {
				Write-LogStep "Marketplace [$name] => $($valid[$name].Repository)"
			}
		}
		foreach ($plugin in ($pluginConfigs.Keys | Sort-Object)) {
			$options = $pluginConfigs[$plugin]
			if ($options -isnot [hashtable]) {
				Write-LogError "AiMarketplaces.PluginConfigs.$plugin is not a hashtable - skipped!"
				continue
			}
			$key = & $pluginKey $plugin
			foreach ($child in ($options.Keys | Sort-Object)) {
				Set-ClaudeSettingsKey -Path "pluginConfigs.$key.$child" -Value $options[$child] -SettingsPath $target.Path | Out-Null
			}
		}
	}
	if ($targets.Count -gt 1) {
		Write-LogWarning "WSL settings carry the marketplaces and options; run `claude plugin marketplace add` and `claude plugin install <plugin>@<marketplace>` inside WSL to install the plugins there."
	}

	if (-not (Get-Command -Name $Command -ErrorAction SilentlyContinue)) {
		Write-LogWarning "Claude Code CLI (claude) not found on PATH - marketplaces are registered in the settings but cannot be added or their plugins installed until the Claude Code CLI is installed!"
		Write-LogSuccess "AI marketplaces deployed!"
		return
	}

	# The CLI knows a marketplace once it has cloned it; the settings key alone takes effect on
	# the engine's next start, so a marketplace the CLI does not list is added here.
	$known = @()
	try {
		$global:LASTEXITCODE = 0
		$listing = (& $Command plugin marketplace list --json 2>$null) -join "`n"
		if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($listing)) {
			$known = @(($listing | ConvertFrom-Json -ErrorAction Stop) | ForEach-Object { [string]$_.name })
		}
	}
	catch {
		Write-LogDebug "claude plugin marketplace list failed => $($_.Exception.Message)"
	}
	foreach ($name in $valid.Keys) {
		if ($known -contains $name) {
			Write-LogStep "Marketplace [$name] already added"
			continue
		}
		try {
			$global:LASTEXITCODE = 0
			& $Command plugin marketplace add $valid[$name].Repository *> $null
			if ($LASTEXITCODE -eq 0) {
				Write-LogSuccess "Added marketplace [$name] ($($valid[$name].Repository))"
			}
			else {
				Write-LogError "claude plugin marketplace add [$($valid[$name].Repository)] failed (exit code $LASTEXITCODE) - run it by hand to see why!"
			}
		}
		catch {
			Write-LogError "claude plugin marketplace add [$($valid[$name].Repository)] threw => $($_.Exception.Message)"
		}
	}

	$wanted = @()
	foreach ($name in $valid.Keys) {
		foreach ($plugin in $valid[$name].Plugins) { $wanted += "$plugin@$name" }
	}
	if ($wanted.Count -eq 0) {
		Write-LogSuccess "AI marketplaces deployed!"
		return
	}

	$installed = @()
	try {
		$global:LASTEXITCODE = 0
		$listing = (& $Command plugin list --json 2>$null) -join "`n"
		if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($listing)) {
			$installed = @(($listing | ConvertFrom-Json -ErrorAction Stop) | ForEach-Object { [string]$_.id })
		}
	}
	catch {
		Write-LogDebug "claude plugin list failed => $($_.Exception.Message)"
	}

	foreach ($id in $wanted) {
		if ($installed -contains $id) {
			Write-LogStep "Plugin [$id] already installed"
			continue
		}
		try {
			$global:LASTEXITCODE = 0
			& $Command plugin install $id *> $null
			if ($LASTEXITCODE -eq 0) {
				Write-LogSuccess "Installed plugin [$id]"
			}
			else {
				Write-LogError "claude plugin install [$id] failed (exit code $LASTEXITCODE) - run it by hand to see why!"
			}
		}
		catch {
			Write-LogError "claude plugin install [$id] threw => $($_.Exception.Message)"
		}
	}

	Write-LogSuccess "AI marketplaces deployed!"
}
