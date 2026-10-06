function Deploy-AiMarketplaces {
	<#
	.SYNOPSIS
		Registers the configured Claude Code plugin marketplaces, writes the variables and options their plugins need into the user settings, and installs the plugins through the Claude Code CLI.

	.DESCRIPTION
		Claude Code plugins published through a marketplace (a repository carrying
		.claude-plugin\marketplace.json) are installed with `claude plugin marketplace add` and
		`claude plugin install <plugin>@<marketplace>`, and the engine then keeps them updated.
		That is a per-machine, per-user action, so this function makes it part of Bootstrap:

		1. Marketplaces in the settings: for every entry of AiMarketplaces.Marketplaces it sets
		   `extraKnownMarketplaces.<name>` of the user's ~\.claude\settings.json to the GitHub
		   source of the repository (through Set-ClaudeSettingsKey, every other setting kept),
		   so Claude Code knows the marketplace on every start.
		2. Variables: every entry of a marketplace's Env is written to the `env` block of the
		   same file (through Set-ClaudeSettingsEnv, every other variable kept), because Claude
		   Code reads its own environment from there in every session, the desktop app's
		   included. That is where a switch the plugins need goes, such as
		   CLAUDE_CODE_ENABLE_FUNCTION_HOOKS = "1", which Claude Code 2.1.286 needs before it
		   loads any hooks module; a plugin cannot set it, since none of its code runs until
		   the switch is on. Values are strings; a name must be a valid variable name.
		   Marketplaces are written in name order, so a variable two of them name ends with
		   the value of the last.
		3. Options: every entry of AiMarketplaces.PluginConfigs is written beneath the plugin's
		   `pluginConfigs` entry, one child key at a time, so an option the user set through
		   /plugin and the repository does not name survives while the repository's values win
		   for the keys it names. A plugin a configured marketplace lists is keyed the way an
		   installed plugin is, `pluginConfigs.<plugin>@<marketplace>`; any other name is
		   written as given (`pluginConfigs.<name>`, the shape of a folder-loaded plugin).
		4. The CLI: when the Claude Code CLI is on PATH, every configured marketplace that
		   `claude plugin marketplace list --json` does not show is added with
		   `claude plugin marketplace add <owner/name>` (the settings key alone takes effect
		   only on the engine's next start), and every plugin an entry's Plugins lists is
		   installed as <plugin>@<marketplace> unless `claude plugin list --json` already
		   shows it. A missing CLI only produces a warning - the settings are deployed
		   regardless, so installing the CLI and running Bootstrap again finishes the job.
		   Already installed plugins are left to `claude plugin update`.

		Inside WSL the same marketplaces, variables and options are written to the WSL user's settings file
		(/home/<DefaultWSLUsername>/.claude/settings.json through the \\wsl.localhost\<distro>
		share) when a WSL distribution and user are configured, and step 4 runs again against
		the Claude Code CLI installed inside WSL, through `wsl -d <distro> -u <user>` and a login
		shell. A `claude` that WSL resolves under /mnt/ is the Windows CLI reached through
		interop, which would install into the Windows profile, so it counts as missing there.

		Mods loaded from a folder (Deploy-AiMods) and plugins installed from a marketplace are
		two ways to load the same plugin: give each plugin one of them, not both. A folder in a
		settings file's env.CLAUDE_CODE_PLUGIN_DIRS that holds a plugin this function installs
		is reported (never removed): Claude Code would load that plugin twice, and the folder
		copy reads its options from pluginConfigs.<plugin>, not <plugin>@<marketplace>. A
		development clone belongs in `claude --plugin-dir <clone>` for one session instead.

		Idempotent: a marketplace already known and a plugin already installed are reported and
		left alone. Called by Bootstrap when the opt-in BootstrapConfig.Steps.AiMarketplaces
		toggle is enabled (OFF by default); the base configuration names no marketplaces, so a
		vanilla run deploys nothing.

	.PARAMETER Command
		The Claude Code CLI to call. Defaults to `claude`; tests pass a stub script.

	.PARAMETER WslCommand
		The WSL launcher to reach the Claude Code CLI inside WSL through. Defaults to `wsl`;
		tests pass a stub script.

	.EXAMPLE
		Deploy-AiMarketplaces
		Registers every configured marketplace, writes the variables and options and installs the plugins, on Windows and inside WSL.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string]$Command = 'claude',

		[Parameter()]
		[string]$WslCommand = 'wsl'
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
	$wsl = $null
	if ($paths.WSLSettingsPath) {
		if (Test-WSLDistributionInstalled) {
			$distro = [string](Get-ConfigSetting -Path 'DefaultWSLDistribution')
			$wsl = @{ Distro = $distro; User = [string](Get-ConfigSetting -Path 'DefaultWSLUsername') }
			$sharePath = "\\wsl.localhost\$distro" + $paths.WSLSettingsPath.Replace('/', '\')
			if (Test-Path -LiteralPath (Split-Path -Parent (Split-Path -Parent $sharePath))) {
				$targets += @{ Label = "WSL"; Path = $sharePath; Share = "\\wsl.localhost\$distro"; Home = Split-Path -Parent (Split-Path -Parent $sharePath) }
			}
			else {
				Write-LogWarning "WSL share for [$distro] unreachable - the WSL Claude Code settings were not updated!"
			}
		}
	}

	# Validated once: a marketplace entry is a GitHub repository, an optional plugin list and the
	# optional variables its plugins need Claude Code to read from the settings file.
	$valid = [ordered]@{}
	foreach ($name in ($marketplaces.Keys | Sort-Object)) {
		$entry = $marketplaces[$name]
		$repository = if ($entry -is [hashtable]) { [string]$entry.Repository } else { "" }
		if ($repository -notmatch '^[\w.-]+/[\w.-]+$') {
			Write-LogError "Marketplace [$name] has no valid Repository (owner/name) - skipped!"
			continue
		}
		$plugins = if ($entry.Plugins) { @($entry.Plugins | ForEach-Object { [string]$_ } | Where-Object { $_ }) } else { @() }
		$variables = [ordered]@{}
		if ($entry.Env -is [hashtable]) {
			foreach ($variable in ($entry.Env.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
				if ($variable -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
					Write-LogError "Marketplace [$name] names an invalid environment variable [$variable] - skipped!"
					continue
				}
				$variables[$variable] = [string]$entry.Env[$variable]
			}
		}
		elseif ($null -ne $entry.Env) {
			Write-LogError "Marketplace [$name] has an Env that is not a hashtable - its variables were skipped!"
		}
		$valid[$name] = @{ Repository = $repository; Plugins = $plugins; Env = $variables }
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

	# One copy per plugin: a folder listed in CLAUDE_CODE_PLUGIN_DIRS that holds a plugin a
	# marketplace here installs loads it a second time, with the options of pluginConfigs.<plugin>
	# instead of <plugin>@<marketplace>. Reported, never removed: the entry is the user's.
	$reportDuplicates = {
		param($Target)
		if (-not (Test-Path -LiteralPath $Target.Path)) { return }
		try {
			$document = Get-Content -LiteralPath $Target.Path -Raw | ConvertFrom-Json -ErrorAction Stop
		}
		catch {
			return
		}
		$dirs = if ($document.env) { [string]$document.env.CLAUDE_CODE_PLUGIN_DIRS } else { "" }
		if (-not $dirs) { return }
		$separator = if ($Target.Share) { ':' } else { ';' }
		foreach ($entry in ($dirs.Split($separator) | Where-Object { $_.Trim() })) {
			# A WSL entry is read from Windows: /mnt/<d>/... is drive <d>, ~ is the WSL home,
			# any other absolute path is on the share.
			$folder = $entry.Trim()
			if ($Target.Share) {
				if ($folder -match '^/mnt/([a-zA-Z])(/.*)?$') { $folder = "$($Matches[1]):" + ([string]$Matches[2]).Replace('/', '\') }
				elseif ($folder -like '~*') { $folder = $Target.Home + $folder.Substring(1).Replace('/', '\') }
				else { $folder = $Target.Share + $folder.Replace('/', '\') }
			}
			elseif ($folder -like '~*') {
				$folder = $HOME + $folder.Substring(1)
			}
			$manifest = Join-Path $folder ".claude-plugin\plugin.json"
			if (-not (Test-Path -LiteralPath $manifest)) { continue }
			try {
				$name = [string](Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json -ErrorAction Stop).name
			}
			catch {
				continue
			}
			$id = & $pluginKey $name
			if ($id -ne $name) {
				Write-LogWarning "Plugin [$id] is installed from its marketplace and also loaded from [$($entry.Trim())] in env.CLAUDE_CODE_PLUGIN_DIRS of [$($Target.Path)] - Claude Code loads two copies, and the folder copy ignores the options under pluginConfigs.$id! Remove that entry and load a development clone with ``claude --plugin-dir <clone>`` for one session instead."
			}
		}
	}

	# Step 4 against one Claude Code CLI: $Invoke runs it with the given arguments and leaves its
	# exit code in $LASTEXITCODE, so Windows and WSL share every check and message.
	$deployThroughCli = {
		param([string]$Label, [string]$Where, [scriptblock]$Invoke)

		# The CLI knows a marketplace once it has cloned it; the settings key alone takes effect
		# on the engine's next start, so a marketplace the CLI does not list is added here.
		$known = @()
		try {
			$global:LASTEXITCODE = 0
			$listing = (& $Invoke plugin marketplace list --json 2>$null) -join "`n"
			if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($listing)) {
				$known = @(($listing | ConvertFrom-Json -ErrorAction Stop) | ForEach-Object { [string]$_.name })
			}
		}
		catch {
			Write-LogDebug "${Label}claude plugin marketplace list failed => $($_.Exception.Message)"
		}
		foreach ($name in $valid.Keys) {
			if ($known -contains $name) {
				Write-LogStep "${Label}Marketplace [$name] already added"
				continue
			}
			try {
				$global:LASTEXITCODE = 0
				& $Invoke plugin marketplace add $valid[$name].Repository *> $null
				if ($LASTEXITCODE -eq 0) {
					Write-LogSuccess "${Label}Added marketplace [$name] ($($valid[$name].Repository))"
				}
				else {
					Write-LogError "${Label}claude plugin marketplace add [$($valid[$name].Repository)] failed (exit code $LASTEXITCODE) - run it by hand$Where to see why!"
				}
			}
			catch {
				Write-LogError "${Label}claude plugin marketplace add [$($valid[$name].Repository)] threw => $($_.Exception.Message)"
			}
		}

		if ($wanted.Count -eq 0) { return }

		$installed = @()
		try {
			$global:LASTEXITCODE = 0
			$listing = (& $Invoke plugin list --json 2>$null) -join "`n"
			if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($listing)) {
				$installed = @(($listing | ConvertFrom-Json -ErrorAction Stop) | ForEach-Object { [string]$_.id })
			}
		}
		catch {
			Write-LogDebug "${Label}claude plugin list failed => $($_.Exception.Message)"
		}

		foreach ($id in $wanted) {
			if ($installed -contains $id) {
				Write-LogStep "${Label}Plugin [$id] already installed"
				continue
			}
			try {
				$global:LASTEXITCODE = 0
				& $Invoke plugin install $id *> $null
				if ($LASTEXITCODE -eq 0) {
					Write-LogSuccess "${Label}Installed plugin [$id]"
				}
				else {
					Write-LogError "${Label}claude plugin install [$id] failed (exit code $LASTEXITCODE) - run it by hand$Where to see why!"
				}
			}
			catch {
				Write-LogError "${Label}claude plugin install [$id] threw => $($_.Exception.Message)"
			}
		}
	}

	foreach ($target in $targets) {
		Write-LogStep "[$($target.Label)] $($target.Path)"
		foreach ($name in $valid.Keys) {
			$source = @{ source = @{ source = "github"; repo = $valid[$name].Repository } }
			if (Set-ClaudeSettingsKey -Path "extraKnownMarketplaces.$name" -Value $source -SettingsPath $target.Path) {
				Write-LogStep "Marketplace [$name] => $($valid[$name].Repository)"
			}
		}
		foreach ($name in $valid.Keys) {
			foreach ($variable in $valid[$name].Env.Keys) {
				if (Set-ClaudeSettingsEnv -Name $variable -Value $valid[$name].Env[$variable] -SettingsPath $target.Path) {
					Write-LogStep "Variable [$variable] => $($valid[$name].Env[$variable]) (marketplace [$name])"
				}
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
		& $reportDuplicates $target
	}

	$wanted = @()
	foreach ($name in $valid.Keys) {
		foreach ($plugin in $valid[$name].Plugins) { $wanted += "$plugin@$name" }
	}

	if (Get-Command -Name $Command -ErrorAction SilentlyContinue) {
		& $deployThroughCli -Label "" -Where "" -Invoke { & $Command @args }
	}
	else {
		Write-LogWarning "Claude Code CLI (claude) not found on PATH - marketplaces are registered in the settings but cannot be added or their plugins installed until the Claude Code CLI is installed!"
	}

	if ($wsl -and $wsl.Distro -and $wsl.User) {
		# A login shell, so the PATH a WSL user's profile sets (~/.local/bin, npm) is the one used.
		$invokeWsl = { & $WslCommand -d $wsl.Distro -u $wsl.User -e sh -lc 'PATH=$HOME/.local/bin:$PATH; claude $*' claude @args }
		$global:LASTEXITCODE = 0
		$resolved = try { ((& $WslCommand -d $wsl.Distro -u $wsl.User -e sh -lc 'PATH=$HOME/.local/bin:$PATH; command -v claude' 2>$null) -join "").Trim() } catch { "" }
		if ($LASTEXITCODE -ne 0 -or -not $resolved) {
			Write-LogWarning "Claude Code CLI (claude) not found inside WSL [$($wsl.Distro)] - the WSL settings carry the marketplaces, but their plugins are installed there only once the Claude Code CLI is installed inside WSL!"
		}
		elseif ($resolved -like "/mnt/*") {
			Write-LogWarning "WSL [$($wsl.Distro)] resolves claude to the Windows CLI [$resolved], which would install into the Windows profile - install the Claude Code CLI inside WSL so its plugins are installed there!"
		}
		else {
			& $deployThroughCli -Label "[WSL] " -Where " inside WSL" -Invoke $invokeWsl
		}
	}

	Write-LogSuccess "AI marketplaces deployed!"
}
