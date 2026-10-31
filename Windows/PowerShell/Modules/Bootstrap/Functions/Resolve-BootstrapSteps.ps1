function Resolve-BootstrapSteps {
	<#
	.SYNOPSIS
		Resolves which Bootstrap provisioning steps should run.

	.DESCRIPTION
		Single-pass tri-state resolution (via Resolve-Steps) for every
		Bootstrap step. Per step, -Skip beats -Include beats config
		(BootstrapConfig.Steps.<Name> in $global:Configuration - a plain
		boolean, or a per-machine-type hashtable with a Default fallback)
		beats the built-in defaults.

		Most steps default on because their functions no-op when their
		configuration section is empty - the empty base config makes an
		enabled step apply nothing. The opt-in exceptions default off
		because they have no configuration to be empty and act the moment
		they run: MicrosoftActivationScripts, Win11Debloat, RepositoryUpdate
		(clones and pulls every repository the machine's scope names),
		DeveloperMode, NuGetConfig (prompts for a GitHub PAT), NpmConfig
		(prompts for a GitHub PAT for the npm registries), UpgradeAll
		(upgrades every package already on the machine, not just WinuX's own),
		AiArtifacts (machine-global AI skills, mods, rules, prompts and agents
		links), AiMarketplaces (Claude Code plugin
		marketplaces in the user settings and `claude plugin install`), AiMcpServers
		(MCP servers added to Claude Code and Codex), AiProfileInit (walks the
		AI profile's sign-ins with Initialize-AiProfile, waiting at the terminal, so an
		unattended run leaves it off), ObsidianCli (turns the Obsidian command line
		interface on in Obsidian's per-machine app settings), VSCodeProfiles
		(links VS Code profile files, registers profiles in VS Code's state and
		installs extensions), and LockedStartLayout.

		Returns an ordered hashtable of step name -> boolean, in Bootstrap
		execution order. Bootstrap calls this exactly once per invocation.
		The only side effect is a warning for each step that appears in both
		-Skip and -Include (the step is skipped), so it is also safe to call
		ad hoc to inspect what a Bootstrap invocation would do with the
		current config.

	.PARAMETER Skip
		Step names forced off for this invocation. Wins over -Include with a
		warning when the same name appears in both.

	.PARAMETER Include
		Step names forced on for this invocation, overriding config.

	.EXAMPLE
		Resolve-BootstrapSteps
		Returns the step map a parameterless Bootstrap would use with the current config.

	.EXAMPLE
		Resolve-BootstrapSteps -Skip UpgradeAll, WSL
		Returns the map with UpgradeAll and WSL forced off.
	#>
	[CmdletBinding()]
	[OutputType([System.Collections.Specialized.OrderedDictionary])]
	param(
		[Parameter()]
		[string[]]$Skip,

		[Parameter()]
		[string[]]$Include
	)

	# Built-in defaults, in Bootstrap execution order. The first three only
	# run inside -WithInitialSetup. RepositoryUpdate decides WHETHER the
	# repository step runs at all; WHICH groups it then pulls stays
	# BootstrapConfig.RepositoryUpdateScope's job.
	$defaults = [ordered]@{
		RenameMachine              = $true
		MicrosoftActivationScripts = $false
		Win11Debloat               = $false
		RepositoryUpdate           = $false
		ExecutionPolicy            = $true
		DeveloperMode              = $false
		PowerPlan                  = $true
		PowerButtonActions         = $true
		SystemTheme                = $true
		Locale                     = $true
		DisplayLanguage            = $true
		KeyboardLayouts            = $true
		NerdFont                   = $true
		PowerShellModules          = $true
		SpecialFolders             = $true
		WSL                        = $true
		WinGetApps                 = $true
		ScoopApps                  = $true
		ChocolateyApps             = $true
		UpgradeAll                 = $false
		DotnetEf                   = $true
		EnvironmentVariables       = $true
		CondaEnvironments          = $true
		NuGetConfig                = $false
		NpmConfig                  = $false
		Taskbar                    = $true
		SymbolicLinks              = $true
		AiArtifacts                = $false
		AiMarketplaces             = $false
		AiMcpServers               = $false
		AiProfileInit              = $false
		ObsidianCli                = $false
		VSCodeProfiles             = $false
		LockedStartLayout          = $false
	}

	$configSteps = $null
	$bootstrapConfig = Get-ConfigSetting -Path 'BootstrapConfig'
	if ($bootstrapConfig -is [hashtable]) {
		$configSteps = $bootstrapConfig.Steps
	}

	return Resolve-Steps -Defaults $defaults -ConfigSteps $configSteps -Skip $Skip -Include $Include
}
