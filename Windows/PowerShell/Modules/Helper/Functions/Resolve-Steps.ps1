function Resolve-Steps {
	<#
	.SYNOPSIS
		Resolves which steps of a configurable step set should run.

	.DESCRIPTION
		Single-pass tri-state resolution shared by every step-map consumer
		(Resolve-KillAllSteps, Resolve-BootstrapSteps). Per step, -Skip beats
		-Include beats config (-ConfigSteps.<Name> - a plain boolean, or a
		per-machine-type hashtable with a Default fallback, the
		BootstrapConfig.Steps.WSL shape) beats the built-in -Defaults.

		$false is a real config value, so booleans resolve with explicit $null
		checks - truthiness would misread them.

		Returns an ordered hashtable of step name -> boolean, in the order the
		-Defaults dictionary defines. The only side effect is a warning for
		each step that appears in both -Skip and -Include (the step is
		skipped), so it is also safe to call ad hoc to inspect what an
		invocation would do with the current config.

	.PARAMETER Defaults
		Ordered dictionary of step name -> built-in boolean default. Defines
		both the step set and the execution order of the returned map.

	.PARAMETER ConfigSteps
		The configuration Steps hashtable to layer over the defaults, or $null
		when the section is not configured.

	.PARAMETER Skip
		Step names forced off for this invocation. Wins over -Include with a
		warning when the same name appears in both.

	.PARAMETER Include
		Step names forced on for this invocation, overriding config.

	.EXAMPLE
		Resolve-Steps -Defaults ([ordered]@{ Docker = $true }) -ConfigSteps $global:Configuration.KillAll.Steps
		Returns the step map the current config produces for the given defaults.

	.EXAMPLE
		Resolve-Steps -Defaults $defaults -ConfigSteps $configSteps -Skip Docker, Browsers
		Returns the map with Docker and Browsers forced off.
	#>
	[CmdletBinding()]
	[OutputType([System.Collections.Specialized.OrderedDictionary])]
	param(
		[Parameter(Mandatory)]
		[System.Collections.Specialized.OrderedDictionary]$Defaults,

		[Parameter()]
		[hashtable]$ConfigSteps,

		[Parameter()]
		[string[]]$Skip,

		[Parameter()]
		[string[]]$Include
	)

	$states = [ordered]@{}
	foreach ($name in $Defaults.Keys) {
		if ($Skip -contains $name) {
			if ($Include -contains $name) {
				Write-LogWarning "Step [$name] is in both -Skip and -Include - skipping it!"
			}
			$states[$name] = $false
			continue
		}

		if ($Include -contains $name) {
			$states[$name] = $true
			continue
		}

		$resolved = $Defaults[$name]
		if ($ConfigSteps -is [hashtable] -and $ConfigSteps.ContainsKey($name)) {
			$value = $ConfigSteps[$name]

			if ($value -is [bool]) {
				$resolved = $value
			}
			elseif ($value -is [hashtable]) {
				if ($global:MachineType -and $null -ne $value[$global:MachineType]) {
					$resolved = [bool]$value[$global:MachineType]
				}
				elseif ($null -ne $value.Default) {
					$resolved = [bool]$value.Default
				}
			}
		}

		$states[$name] = $resolved
	}

	return $states
}
