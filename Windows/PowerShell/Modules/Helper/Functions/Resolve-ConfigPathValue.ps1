function Resolve-ConfigPathValue {
	<#
	.SYNOPSIS
		Traverse dot-notation path in configuration hashtable.

	.DESCRIPTION
		Navigates nested hashtable using dot notation (e.g., 'Projects.Self.Root').
		Returns the value at path end or $null if any segment missing.

	.PARAMETER PathExpression
		Dot-separated path string (e.g., 'Universal.DefaultBrowser').

	.EXAMPLE
		$value = Resolve-ConfigPathValue -PathExpression "Projects.Self.Root"
		Write-Host "Value: $value"
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string]$PathExpression
	)

	if ([string]::IsNullOrWhiteSpace($PathExpression)) {
		return $null
	}

	$current = $MachineSpecificPaths
	foreach ($property in $PathExpression.Split('.')) {
		if ($null -eq $current) {
			return $null
		}

		$current = $current.$property
	}

	return $current
}
