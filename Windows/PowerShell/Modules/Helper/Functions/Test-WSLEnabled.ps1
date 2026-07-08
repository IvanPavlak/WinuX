function Test-WSLEnabled {
	<#
	.SYNOPSIS
		Check if Windows Subsystem for Linux is installed and available.

	.DESCRIPTION
		Runs `wsl --status` and returns $false if WSL not installed, $true if available.

	.EXAMPLE
		if (Test-WSLEnabled) { Write-Host "WSL is ready" }
	#>
	$wslStatus = wsl --status 2>&1
	return -not ($wslStatus -like "*WSL is not installed*")
}
