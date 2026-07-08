function Test-AdminPrivileges {
	<#
	.SYNOPSIS
		Verify or request Administrator privileges.

	.DESCRIPTION
		Checks if script is running as Administrator. With -CheckOnly, returns boolean.
		Without -CheckOnly, prompts user to elevate if not admin and offers to rerun in elevated shell.

	.PARAMETER CheckOnly
		If specified, only return boolean without prompting or elevating.

	.EXAMPLE
		if (Test-AdminPrivileges -CheckOnly) { Write-Host "Running as admin" }
		Test-AdminPrivileges  # Prompts to elevate if not admin
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[switch]$CheckOnly
	)

	$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
	$principal = New-Object Security.Principal.WindowsPrincipal($identity)

	if ($CheckOnly) {
		return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
	}

	if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
		$currentDirectory = (Get-Location).Path
		$triggeringCommand = (Get-PSCallStack)[1].InvocationInfo.Line

		Write-LogError "This must be run with Administrator privileges!"

		$openConfirmation = Resolve-Selection `
			-MenuTitle "[Open Administrator PowerShell]" `
			-PromptMessage "Do you want to open the Administrator PowerShell and rerun the command? (Enter for default => Yes)" `
			-AllowEmptyPromptResponse:$true

		if ($openConfirmation -eq "Yes" -or $null -eq $openConfirmation) {
			$triggeringCommandFromCurrentDirectory = "Set-Location -Path '$currentDirectory'; $triggeringCommand"
			t -Administrator $triggeringCommandFromCurrentDirectory
		}

		throw [System.Management.Automation.PipelineStoppedException]::new()

		Write-LogSuccess "Rerunning [$triggeringCommand] in the Administrator PowerShell!"
	}
}
