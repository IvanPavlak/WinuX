function Install-Git {
	<#
	.SYNOPSIS
		Installs Git via winget and configures global user name, email, and long path support.

	.DESCRIPTION
		If `git` is not already available, installs it using the WinGet package ID from
		the `GitConfig.WingetPackageId` key in Configuration.psd1. After installation,
		refreshes the current session PATH.

		Then applies these global git settings from the `GitConfig` section:
		- `user.name`  - from `GitConfig.UserName`
		- `user.email` - from `GitConfig.UserEmail`
		- `core.longpaths true` - required for the Obsidian repository (very long filenames)

		Called automatically by Bootstrap.

	.EXAMPLE
		Install-Git
		Installs and configures Git, or re-applies git config if already installed.
	#>
	$gitConfig = $Configuration.GitConfig
	if (-not $gitConfig) {
		Write-LogError "Error: GitConfig block not found in configuration!"
		return
	}

	if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
		Write-LogTitle "Installing Git via winget"
		winget install --id $gitConfig.WingetPackageId -e --source winget --accept-package-agreements --accept-source-agreements
		$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
	}

	Write-LogTitle "Configuring Git global settings"

	git config --global user.name $gitConfig.UserName
	git config --global user.email $gitConfig.UserEmail
	git config --system core.longpaths true # Allows cloning of the Obsidian repository which has very long filenames

	$gitName = git config --global user.name
	$gitEmail = git config --global user.email

	Write-Host -ForegroundColor Green "`n[Git Configuration]"
	Write-Host -ForegroundColor Green "  Name => $gitName"
	Write-Host -ForegroundColor Green "  Email => $gitEmail"
}
