function Custom-ReadHost {
	<#
	.SYNOPSIS
		Prompt user for input with customizable colors and formatting.

	.DESCRIPTION
		Wrapper around Read-Host with support for colored prompts, optional newlines, and secure string input.
		Used throughout modules for user interaction with consistent styling.

	.PARAMETER PromptMessage
		The message to display (required).

	.PARAMETER ForegroundColor
		Console color for prompt text (default: White).

	.PARAMETER AddNewLine
		If $true, add newline before prompt (default: $true).

	.PARAMETER AsSecureString
		If specified, return input as SecureString for passwords.

	.EXAMPLE
		$input = Custom-ReadHost -PromptMessage "Enter value: " -ForegroundColor Yellow
		$password = Custom-ReadHost -PromptMessage "Enter password: " -AsSecureString
	#>
	param (
		[Parameter(Mandatory = $true)]
		[string]$PromptMessage,

		[Parameter(Mandatory = $false)]
		[string]$ForegroundColor = "White",

		[Parameter(Mandatory = $false)]
		[switch]$AddNewLine = $true,

		[Parameter(Mandatory = $false)]
		[switch]$AsSecureString
	)

	$prefix = if ($AddNewLine) { "`n" } else { "" }

	Write-Host -ForegroundColor $ForegroundColor -NoNewline "$prefix$PromptMessage"

	if ($AsSecureString) {
		return Read-Host -AsSecureString
	}
 else {
		return Read-Host
	}
}
