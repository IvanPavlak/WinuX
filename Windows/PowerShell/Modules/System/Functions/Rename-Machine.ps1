function Rename-Machine {
	<#
    .SYNOPSIS
        Sets the machine hostname from Configuration.psd1 or prompts for a new name.

    .DESCRIPTION
        Reads the configured hostnames from `HostnameToMachineType` in Configuration.psd1.
        If the current hostname matches a configured name, skips the operation (idempotent).
        With `-Override`, allows re-entry of a new hostname even if already configured.
        Requires administrator privileges.

    .PARAMETER Override
        Force reconfiguration of the hostname even if it's already set.

    .EXAMPLE
        Rename-Machine
        Sets the hostname if not already configured. Shows the configured hostname if already set.

    .EXAMPLE
        Rename-Machine -Override
        Prompts for a new hostname, ignoring the current one.
    #>
	param (
		[switch]$Override
	)

	Test-AdminPrivileges

	Write-LogTitle "Setup Machine Name"

	$skipHostnames = @($global:Configuration.HostnameToMachineType.Keys)
	$currentHostname = $env:COMPUTERNAME

	if (($skipHostnames -contains $currentHostname) -and -not $Override) {
		Write-LogWarning "Machine name already configured correctly to => [${currentHostname}]"
		return
	}

	if ($Override) {
		Write-LogStep " Current Hostname => [$currentHostName]"

		$keepOrRenameChoice = Resolve-Selection `
			-OptionList @("Enter new name", "Keep current") `
			-PromptMessage "Choose an option" `
			-HideMenuTitle `

		if ($keepOrRenameChoice -eq "Keep current") {
			Write-LogSuccess "Keeping current hostname => [$currentHostName]"
			return
		}
	}
	else {
		$selection = Resolve-Selection `
			-PromptMessage "Do you want to rename the machine? (Press Enter for default => No)" `
			-HideMenuTitle `
			-AllowEmptyPromptResponse:$true

		if ($null -eq $selection -or $selection -eq "No") {
			Write-LogWarning "Machine renaming skipped!"
			return
		}
	}

	while ($true) {
		$newName = Custom-ReadHost "`nProvide new machine name (or press Enter to cancel): " -AddNewLine:$false

		if ([string]::IsNullOrWhiteSpace($newName)) {
			Write-LogError "Machine renaming cancelled!"
			return
		}

		# Validate the new name against Windows naming rules
		$isValid = $true
		if ($newName.Length -gt 63) {
			Write-LogError "Name cannot be longer than 63 characters!"
			$isValid = $false
		}
		if ($newName -match '^\d+$') {
			Write-LogError "Name cannot consist entirely of numbers!"
			$isValid = $false
		}
		if ($newName -notmatch '^[a-zA-Z0-9-]+$') {
			Write-LogError "Name can only contain letters (a-z), numbers (0-9), and hyphens (-)!"
			$isValid = $false
		}

		if ($isValid) {
			try {
				Write-LogSuccess "Renaming machine to [$newName]!"
				Rename-Computer -NewName $newName -LocalCredential $env:Username -ErrorAction Stop
				Write-LogSuccess "Success! Restart the computer for the change to take effect!"
				break
			}
			catch {
				Write-LogError "Error: $($_.Exception.Message)"
			}
		}
		else {
			Write-LogStep " Try again!"
		}
	}
}
