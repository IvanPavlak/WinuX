function Show-FunctionDetails {
	<#
	.SYNOPSIS
		Display formatted function parameter and description details.

	.DESCRIPTION
		Renders function info using colors from Configuration.ShowFunctionDetailsColors.
		Shows function name, description, and all parameters with distinct colors per parameter.

	.PARAMETER FunctionName
		Name of the function being detailed (required).

	.PARAMETER FunctionInfo
		Hashtable with function metadata including Description and parameters (required).

	.EXAMPLE
		$info = @{ Description = "Opens browser"; Url = "https://example.com" }
		Show-FunctionDetails -FunctionName "Open-Browser" -FunctionInfo $info
	#>
	param (
		[Parameter(Mandatory = $true)]
		[string]$FunctionName,

		[Parameter(Mandatory = $true)]
		[System.Collections.IDictionary]$FunctionInfo
	)

	$colors = $global:Configuration.ShowFunctionDetailsColors
	$colorPalette = $colors.Parameters
	$colorIndex = 0

	Write-Host -ForegroundColor $colors.FunctionName " $FunctionName"

	if ($FunctionInfo.Contains('Description')) {
		Write-Host -ForegroundColor $colors.Description "  $($FunctionInfo['Description'])"
	}

	[string]$indent = "  "
	foreach ($key in ($FunctionInfo.Keys | Where-Object { $_ -ne 'Description' })) {
		$value = $FunctionInfo[$key]
		$currentColor = $colorPalette[$colorIndex % $colorPalette.Count]
		$indent += "  "
		$padding = " " * ($key.Length + 4)
		$formattedValue = $value -replace "`n", ("`n" + $indent + $padding)
		Write-Host -ForegroundColor $currentColor -Object "$indent$key => $formattedValue"
		$colorIndex++
	}

	Write-Host ""
}
