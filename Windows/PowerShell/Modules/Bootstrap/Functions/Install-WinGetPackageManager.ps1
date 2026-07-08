function Install-WinGetPackageManager {
	<#
    .SYNOPSIS
        Installs the WinGet package manager if it is not already present.

    .DESCRIPTION
        Checks whether the `winget` command is available. If already installed, reports the
        current version and returns. If missing, installs the community `winget-install` script
        from the PowerShell Gallery via Install-Script and runs it to provision WinGet.

        Called automatically by Bootstrap.

    .EXAMPLE
        Install-WinGetPackageManager
        Installs WinGet or reports that it is already installed.
    #>
	Test-AdminPrivileges

	Write-LogTitle "Installing WinGet"

	try {
		$wingetVersion = winget --version
		Write-LogWarning "WinGet $wingetVersion is already installed!" -BlankLineAfter
		return
	}
	catch {
	}

	try {
		Write-LogStep "Installing WinGet..."
		Install-Script -Name winget-install -Force
		winget-install

		$wingetVersion = winget --version
		Write-LogSuccess "WinGet $wingetVersion installed successfully!"
	}
	catch {
		Write-LogError "Failed to install WinGet: $($_.Exception.Message)" -Exception $_
	}
}
