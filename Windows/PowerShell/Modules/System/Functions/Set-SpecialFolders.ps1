function Set-SpecialFolders {
	<#
	.SYNOPSIS
		Redirects Windows special folders (Documents, Desktop, Downloads) to custom paths.

	.DESCRIPTION
		Reads folder redirections from `SpecialFolders` in Configuration.psd1 and applies them
		via registry entries. Expands placeholder paths (e.g. `{Dev}`, `{User}`) before setting.
		Requires administrator privileges.

	.EXAMPLE
		Set-SpecialFolders
		Redirects all configured special folders.
	#>
	Test-AdminPrivileges

	Write-LogTitle "Redirecting Special Folders"

	$desiredSettings = $Configuration.SpecialFolders
	if (-not $desiredSettings) {
		Write-LogError "Error: SpecialFolders not found in configuration!"
		return
	}

	$basePath = $global:Configuration.BasePaths[$global:MachineType].Dev
	$userPath = $global:Configuration.BasePaths[$global:MachineType].User

	$allSettingsOk = $true
	$processedSettings = @()

	foreach ($setting in $desiredSettings) {
		$expandedValue = Expand-Hashtable -Source $setting.Value -DevPath $basePath -UserPath $userPath -MachineTypeName $global:MachineType

		$setting.ExpandedValue = $expandedValue
		$processedSettings += $setting

		try {
			$currentValue = Get-ItemPropertyValue -Path $setting.Path -Name $setting.Name -ErrorAction Stop
			if ($currentValue -ne $expandedValue) {
				$allSettingsOk = $false
			}
		}
		catch {
			$allSettingsOk = $false
		}
	}

	if ($allSettingsOk) {
		Write-LogWarning "Special folders already correctly mapped to Desktop!"
	}
	else {
		foreach ($setting in $processedSettings) {
			try {
				if (-not (Test-Path $setting.Path)) {
					New-Item -Path $setting.Path -Force | Out-Null
				}

				Set-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.ExpandedValue -Type ExpandString -Force
				Write-LogSuccess "$($setting.Description) -> $($setting.ExpandedValue)"
			}
			catch {
				Write-LogError "Failed to set folder [$($setting.Description)] => $($_.Exception.Message)"
			}
		}

		Write-LogSuccess "Special folders configuration completed!"
	}
}
