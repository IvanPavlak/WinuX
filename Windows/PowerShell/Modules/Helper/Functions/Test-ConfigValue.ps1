function Test-ConfigValue {
	<#
	.SYNOPSIS
		Tests whether a configuration value is actually configured.

	.DESCRIPTION
		The single "is this configured?" check for the empty-by-default
		configuration. Returns $false for every shape an intentionally empty
		base value takes: $null, an empty or whitespace-only string, an empty
		array/collection, and an empty hashtable/dictionary.

		Exists because bare truthiness gets this wrong in PowerShell: an empty
		hashtable is truthy (-not @{} is $false), so a guard like
		"if (-not $Configuration.WakeOnLanConfig)" silently passes an empty
		section through. Every unconfigured-section guard should use this
		instead of ad hoc -not / .Count checks. For the common
		test-warn-and-return guard shape, use the Confirm-ConfigValue wrapper;
		this pure predicate is for checks that emit no warning (or log with
		custom formatting).

	.PARAMETER Value
		The configuration value to test. Accepts $null.

	.EXAMPLE
		$configMode = if (Test-ConfigValue $Configuration.PowerPlans) { $Configuration.PowerPlans[$MachineType] } else { $null }

	.EXAMPLE
		Test-ConfigValue ""        # $false
		Test-ConfigValue @{}       # $false
		Test-ConfigValue @()       # $false
		Test-ConfigValue @("x")    # $true
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter()]
		[AllowNull()]
		$Value
	)

	if ($null -eq $Value) {
		return $false
	}

	if ($Value -is [string]) {
		return -not [string]::IsNullOrWhiteSpace($Value)
	}

	if ($Value -is [System.Collections.IDictionary]) {
		return $Value.Count -gt 0
	}

	if ($Value -is [System.Collections.ICollection]) {
		return $Value.Count -gt 0
	}

	return $true
}
