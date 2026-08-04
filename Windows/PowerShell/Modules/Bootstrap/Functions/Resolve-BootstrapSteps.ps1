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
		they run: MicrosoftActivationScripts, Win11Debloat, DeveloperMode,
		NuGetConfig (prompts for a GitHub PAT), and LockedStartLayout.

		Legacy alias: when Steps.WSL is absent but the deprecated
		BootstrapConfig.WSLSetup exists, WSL resolves from WSLSetup, so
		forks that predate Steps keep working unmodified.

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
	# run inside -WithInitialSetup; UpdateRepositories has no entry here on
	# purpose - it is governed by BootstrapConfig.RepositoryUpdateScope
	# ("None" is its off switch).
	$defaults = [ordered]@{
		RenameMachine              = $true
		MicrosoftActivationScripts = $false
		Win11Debloat               = $false
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
		UpgradeAll                 = $true
		DotnetEf                   = $true
		EnvironmentVariables       = $true
		CondaEnvironments          = $true
		NuGetConfig                = $false
		Taskbar                    = $true
		SymbolicLinks              = $true
		LockedStartLayout          = $false
	}

	$configSteps = $null
	if ($global:Configuration -and $global:Configuration.BootstrapConfig -is [hashtable]) {
		$configSteps = $global:Configuration.BootstrapConfig.Steps

		# Deprecated-alias fallback: honor WSLSetup only when Steps carries no
		# WSL entry of its own. Work on a copy so the merged global config is
		# never mutated.
		$legacyWslSetup = $global:Configuration.BootstrapConfig.WSLSetup
		if ($null -ne $legacyWslSetup -and -not ($configSteps -is [hashtable] -and $configSteps.ContainsKey('WSL'))) {
			$configSteps = if ($configSteps -is [hashtable]) { $configSteps.Clone() } else { @{} }
			$configSteps['WSL'] = $legacyWslSetup
		}
	}

	return Resolve-Steps -Defaults $defaults -ConfigSteps $configSteps -Skip $Skip -Include $Include
}
