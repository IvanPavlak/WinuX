function Install-ScoopPackageManager {
	<#
	.SYNOPSIS
		Installs the Scoop package manager if not already present.

	.DESCRIPTION
		Checks whether the `scoop` command is available. If not, downloads and runs the
		official Scoop install script from get.scoop.sh with `-RunAsAdmin`. Does nothing
		if Scoop is already installed.

		Called automatically by Bootstrap.

	.EXAMPLE
		Install-ScoopPackageManager
		Installs Scoop or reports that it is already installed.
	#>
	Write-LogTitle "Installing Scoop Package Manager"

	if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
		try {
			Invoke-Expression "& {$(Invoke-RestMethod get.scoop.sh)} -RunAsAdmin"
			Write-LogSuccess "Scoop installed successfully!"
		}
		catch {
			Write-LogError "Error installing Scoop: $_"
		}
	}
	else {
		Write-LogWarning "Scoop is already installed!"
	}
}
