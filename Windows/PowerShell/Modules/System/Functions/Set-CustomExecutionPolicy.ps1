function Set-CustomExecutionPolicy {
	<#
	.SYNOPSIS
		Sets the PowerShell execution policy to Bypass for a specified scope.

	.DESCRIPTION
		Calls `Set-ExecutionPolicy -ExecutionPolicy Bypass`. Used to allow unsigned scripts
		to run within the specified scope without user prompts.

	.PARAMETER Scope
		The scope for the execution policy. Valid values are "Process" (current session only),
		"CurrentUser" (all sessions for current user), or "LocalMachine" (all users, all sessions).
		Defaults to "Process".

	.EXAMPLE
		Set-CustomExecutionPolicy
		Sets execution policy to Bypass for the current process only.

	.EXAMPLE
		Set-CustomExecutionPolicy -Scope CurrentUser
		Sets execution policy to Bypass for all sessions of the current user.
	#>
	param(
		[Parameter(Mandatory = $false)]
		[ValidateSet("Process", "CurrentUser", "LocalMachine")]
		[string]$Scope = "Process"
	)
	Write-LogTitle "Setting execution policy to Bypass for scope: $Scope"
	Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope $Scope -Force
}
