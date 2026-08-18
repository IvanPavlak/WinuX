function Resolve-RunProjectSteps {
	<#
	.SYNOPSIS
		Resolves which optional Run-Project steps should run.

	.DESCRIPTION
		Single-pass tri-state resolution (via Resolve-Steps) for every optional
		Run-Project step. Per step, -Skip beats -Include beats config
		(RunProject.Steps.<Name> in $global:Configuration - a plain boolean, or a
		per-machine-type hashtable with a Default fallback, the
		BootstrapConfig.Steps.WSL shape) beats the built-in defaults.

		Docker is the one step so far: it resolves the project's Docker Compose
		source and starts containers before the project runs. It defaults to on -
		which is inert unless a project's mapping actually declares a database
		provider or UsesDocker - and a setup that runs its databases locally turns
		it off once in Configuration.local.psd1 instead of stripping provider
		metadata from every project mapping.

		$false is a real config value, so booleans resolve with explicit $null
		checks - truthiness would misread them.

		Returns an ordered hashtable of step name -> boolean. Run-Project calls
		this exactly once per invocation. The only side effect is a warning for
		each step that appears in both -Skip and -Include (the step is skipped).

	.PARAMETER Skip
		Step names forced off for this invocation. Wins over -Include with a
		warning when the same name appears in both.

	.PARAMETER Include
		Step names forced on for this invocation, overriding config.

	.EXAMPLE
		Resolve-RunProjectSteps
		Returns the step map a parameterless Run-Project would use with the current config.

	.EXAMPLE
		Resolve-RunProjectSteps -Skip Docker
		Returns the map with Docker forced off.
	#>
	[CmdletBinding()]
	[OutputType([System.Collections.Specialized.OrderedDictionary])]
	param(
		[Parameter()]
		[string[]]$Skip,

		[Parameter()]
		[string[]]$Include
	)

	# Built-in defaults. Docker on by default reproduces the classic behavior:
	# projects without database providers or UsesDocker never touch Docker anyway.
	$defaults = [ordered]@{
		Docker = $true
	}

	$configSteps = $null
	if ($global:Configuration -and $global:Configuration.RunProject -is [hashtable]) {
		$configSteps = $global:Configuration.RunProject.Steps
	}

	return Resolve-Steps -Defaults $defaults -ConfigSteps $configSteps -Skip $Skip -Include $Include
}
