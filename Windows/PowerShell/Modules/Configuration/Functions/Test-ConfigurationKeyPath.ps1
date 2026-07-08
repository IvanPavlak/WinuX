function Test-ConfigurationKeyPath {
	<#
	.SYNOPSIS
		Tests whether a configuration key path resolves to a non-empty value.

	.DESCRIPTION
		Walks a hashtable using the provided key path and returns `$true` only when
		every segment exists and the final resolved value is not `$null` or an empty
		string. Used by `Test-ConfigurationSchema` to validate required settings.

	.PARAMETER Table
		Hashtable to inspect.

	.PARAMETER Path
		Ordered key path to resolve within the hashtable.

	.EXAMPLE
		Test-ConfigurationKeyPath -Table $Configuration -Path @('GitConfig', 'UserName')
		Returns `$true` when `GitConfig.UserName` exists and is not empty.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Table,

		[Parameter(Mandatory = $true)]
		[string[]]$Path
	)

	$current = $Table
	foreach ($segment in $Path) {
		if ($null -eq $current -or -not $current.ContainsKey($segment)) {
			return $false
		}

		$current = $current[$segment]
	}

	return ($null -ne $current -and $current -ne '')
}
