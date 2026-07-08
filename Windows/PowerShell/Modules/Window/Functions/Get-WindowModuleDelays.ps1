function Get-WindowModuleDelays {
	<#
	.SYNOPSIS
		Gets the current Window module timing configuration.

	.DESCRIPTION
		Returns a clone of the module-scoped timing configuration hashtable.
		This allows external tuning of delay values used throughout the module.

	.OUTPUTS
		Hashtable containing timing configuration values in milliseconds.

	.EXAMPLE
		Get-WindowModuleDelays
		Returns the current timing configuration.
	#>
	return $script:WindowModuleDelays.Clone()
}
