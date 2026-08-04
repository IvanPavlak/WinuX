function Resolve-KillAllStep {
	<#
	.SYNOPSIS
		Resolves whether a single Kill-All cleanup step should run.

	.DESCRIPTION
		Tri-state resolution for one Kill-All step: -Skip beats -Include beats
		config (KillAll.Steps.<Name> in $global:Configuration - a plain boolean,
		or a per-machine-type hashtable with a Default fallback, the
		BootstrapConfig.WSLSetup shape) beats the built-in default.

		$false is a real config value, so booleans resolve with explicit $null
		checks - truthiness would misread them.

		Returns $true when the step should run, $false when it should be skipped.

	.PARAMETER Name
		The step name to resolve (e.g. "Docker", "Browsers"). Must match the key
		used in KillAll.Steps and in Kill-All's -Skip/-Include ValidateSet.

	.PARAMETER Default
		The built-in default used when neither parameters nor config decide the
		step (Kill-All passes $true for every step except ReloadProfile).

	.PARAMETER Skip
		Step names forced off for this invocation. Wins over -Include with a
		warning when the same name appears in both.

	.PARAMETER Include
		Step names forced on for this invocation, overriding config.

	.EXAMPLE
		Resolve-KillAllStep -Name "Docker" -Default $true -Skip @("Docker") -Include @()
		Returns $false - the parameter override beats everything.

	.EXAMPLE
		Resolve-KillAllStep -Name "Docker" -Default $true -Skip @() -Include @()
		Returns the KillAll.Steps.Docker config value, or $true when unconfigured.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter(Mandatory = $true)]
		[bool]$Default,

		[Parameter()]
		[string[]]$Skip,

		[Parameter()]
		[string[]]$Include
	)

	if ($Skip -contains $Name) {
		if ($Include -contains $Name) {
			Write-LogWarning "Step [$Name] is in both -Skip and -Include - skipping it!"
		}
		return $false
	}

	if ($Include -contains $Name) {
		return $true
	}

	$steps = $null
	if ($global:Configuration -and $global:Configuration.KillAll -is [hashtable]) {
		$steps = $global:Configuration.KillAll.Steps
	}

	if ($steps -is [hashtable] -and $steps.ContainsKey($Name)) {
		$value = $steps[$Name]

		if ($value -is [bool]) {
			return $value
		}

		if ($value -is [hashtable]) {
			if ($global:MachineType -and $null -ne $value[$global:MachineType]) {
				return [bool]$value[$global:MachineType]
			}
			if ($null -ne $value.Default) {
				return [bool]$value.Default
			}
		}
	}

	return $Default
}
