function Test-AppNotInstalled {
	<#
	.SYNOPSIS
		Check if a Windows Store app is not installed.

	.DESCRIPTION
		Queries installed AppX packages and returns $true if the specified app is not found.
		Returns $false if app is installed.

	.PARAMETER appName
		The name or partial name of the AppX package to check.

	.EXAMPLE
		if (Test-AppNotInstalled -appName "WindowsTerminal") { Write-Host "Install Terminal" }
	#>
	param([string]$appName)
	return !(Get-AppxPackage $appName)
}
