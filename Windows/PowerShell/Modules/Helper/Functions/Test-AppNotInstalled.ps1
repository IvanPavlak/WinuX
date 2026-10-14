function Test-AppNotInstalled {
	<#
	.SYNOPSIS
		Check if a Windows Store app is not installed.

	.DESCRIPTION
		Queries installed AppX packages and returns $true if the specified app is not found.
		Returns $false if app is installed.

	.PARAMETER appName
		The AppX package name to check, passed to Get-AppxPackage -Name. It must be the full
		package name (e.g. "Microsoft.WindowsTerminal"); match a partial name with wildcards
		("*WindowsTerminal*").

	.EXAMPLE
		if (Test-AppNotInstalled -appName "Microsoft.WindowsTerminal") { Write-Host "Install Terminal" }
	#>
	param([string]$appName)
	return !(Get-AppxPackage $appName)
}
