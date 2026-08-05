function Resolve-SystemThemeSteps {
	<#
	.SYNOPSIS
		Resolves which Set-SystemTheme follow-up steps should run.

	.DESCRIPTION
		Single-pass tri-state resolution (via Resolve-Steps) for every
		Set-SystemTheme follow-up step - the actions that run after the theme
		registry values are written. Per step, -Skip beats -Include beats config
		(SystemTheme.Steps.<Name> in $global:Configuration - a plain boolean, or
		a per-machine-type hashtable with a Default fallback, the
		BootstrapConfig.Steps.WSL shape) beats the built-in defaults.

		Everything defaults on except RefreshBrowserTabs. Restarting Explorer is
		what makes the new theme visible on shell chrome, so it belongs to
		applying a theme rather than being collateral of it, and the two
		wallpaper steps no-op when their configuration section is empty - on the
		empty base config an enabled step applies nothing. Reloading every
		browser tab is the one action with real collateral: it takes focus per
		window and hard-reloads pages, discarding unsaved page state. So it is
		the only opt-in step.

		Returns an ordered hashtable of step name -> boolean, in Set-SystemTheme
		execution order. Set-SystemTheme calls this exactly once per invocation.
		The only side effect is a warning for each step that appears in both
		-Skip and -Include (the step is skipped), so it is also safe to call
		ad hoc to inspect what a Set-SystemTheme invocation would do with the
		current config.

	.PARAMETER Skip
		Step names forced off for this invocation. Wins over -Include with a
		warning when the same name appears in both.

	.PARAMETER Include
		Step names forced on for this invocation, overriding config.

	.EXAMPLE
		Resolve-SystemThemeSteps
		Returns the step map a parameterless Set-SystemTheme would use with the current config.

	.EXAMPLE
		Resolve-SystemThemeSteps -Skip SetWallpaper, SetLockScreenWallpaper
		Returns the map with both wallpaper steps forced off.

	.EXAMPLE
		Resolve-SystemThemeSteps -Include RefreshBrowserTabs
		Returns the map with the one off-by-default step forced on.
	#>
	[CmdletBinding()]
	[OutputType([System.Collections.Specialized.OrderedDictionary])]
	param(
		[Parameter()]
		[string[]]$Skip,

		[Parameter()]
		[string[]]$Include
	)

	# Built-in defaults, in Set-SystemTheme execution order. RefreshBrowserTabs only
	# runs when the theme actually changed - reloading tabs that already render
	# the requested theme buys nothing.
	$defaults = [ordered]@{
		RefreshBrowserTabs     = $false
		RestartExplorer        = $true
		SetWallpaper           = $true
		SetLockScreenWallpaper = $true
	}

	$configSteps = $null
	if ($global:Configuration -and $global:Configuration.SystemTheme -is [hashtable]) {
		$configSteps = $global:Configuration.SystemTheme.Steps
	}

	return Resolve-Steps -Defaults $defaults -ConfigSteps $configSteps -Skip $Skip -Include $Include
}
