function Install-ChocolateyPackageManager {
	<#
	.SYNOPSIS
		Installs the Chocolatey package manager if not already present.

	.DESCRIPTION
		Checks whether the `choco` command is available. If not, downloads and runs the
		official Chocolatey install script from chocolatey.org. Does nothing if Chocolatey
		is already installed.

		Called automatically by Bootstrap.

	.EXAMPLE
		Install-ChocolateyPackageManager
		Installs Chocolatey or reports that it is already installed.
	#>
	Write-LogTitle "Installing Chocolatey Package Manager"

	if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
		try {
			Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
			Write-LogSuccess "Chocolatey installed successfully"
		}
		catch {
			Write-LogError "Error installing Chocolatey: $_"
		}
	}
	else {
		Write-LogWarning "Chocolatey is already installed"
	}
}
