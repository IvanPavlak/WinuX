function Add-WindowsFormsType {
	<#
	.SYNOPSIS
		Loads the System.Windows.Forms assembly into the current PowerShell session.

	.DESCRIPTION
		Calls `Add-Type -AssemblyName System.Windows.Forms`. Safe to call multiple times.
		Required by functions that open file-picker dialogs or use Windows Forms controls.

	.PARAMETER Quiet
		Suppresses the status output messages.

	.EXAMPLE
		Add-WindowsFormsType
		Loads System.Windows.Forms and prints a confirmation message.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$Quiet
	)

	if (-not $Quiet) {
		Write-LogTitle "Adding System.Windows.Forms Type"
	}

	try {
		Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
	}
	catch {
		Write-Error "Failed to load System.Windows.Forms assembly => [$_]"
		return @()
	}

	if (-not $Quiet) {
		Write-LogSuccess "Added System.Windows.Forms type successfully!"
	}
}
