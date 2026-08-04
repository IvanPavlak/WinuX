function Resolve-KillAllSteps {
	<#
	.SYNOPSIS
		Resolves which Kill-All cleanup steps should run.

	.DESCRIPTION
		Single-pass tri-state resolution (via Resolve-Steps) for every
		Kill-All step. Per step,
		-Skip beats -Include beats config (KillAll.Steps.<Name> in
		$global:Configuration - a plain boolean, or a per-machine-type hashtable
		with a Default fallback, the BootstrapConfig.Steps.WSL shape) beats the
		built-in defaults (everything on except ReloadProfile).

		$false is a real config value, so booleans resolve with explicit $null
		checks - truthiness would misread them.

		Returns an ordered hashtable of step name -> boolean, in Kill-All
		execution order. Kill-All calls this exactly once per invocation. The
		only side effect is a warning for each step that appears in both -Skip
		and -Include (the step is skipped), so it is also safe to call ad hoc
		to inspect what a Kill-All invocation would do with the current config.

	.PARAMETER Skip
		Step names forced off for this invocation. Wins over -Include with a
		warning when the same name appears in both.

	.PARAMETER Include
		Step names forced on for this invocation, overriding config.

	.EXAMPLE
		Resolve-KillAllSteps
		Returns the step map a parameterless Kill-All would use with the current config.

	.EXAMPLE
		Resolve-KillAllSteps -Skip Docker, Browsers
		Returns the map with Docker and Browsers forced off.
	#>
	[CmdletBinding()]
	[OutputType([System.Collections.Specialized.OrderedDictionary])]
	param(
		[Parameter()]
		[string[]]$Skip,

		[Parameter()]
		[string[]]$Include
	)

	# Built-in defaults, in Kill-All execution order. ReloadProfile is the one
	# opt-in step - reloading the profile has always required asking for it.
	$defaults = [ordered]@{
		VirtualDesktops = $true
		Docker          = $true
		Browsers        = $true
		VisibleWindows  = $true
		NamedProcesses  = $true
		TerminalTabs    = $true
		CenterTerminal  = $true
		FocusTerminal   = $true
		ReloadProfile   = $false
	}

	$configSteps = $null
	if ($global:Configuration -and $global:Configuration.KillAll -is [hashtable]) {
		$configSteps = $global:Configuration.KillAll.Steps
	}

	return Resolve-Steps -Defaults $defaults -ConfigSteps $configSteps -Skip $Skip -Include $Include
}
