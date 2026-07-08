function Set-ExplorerOptions {
	<#
	.SYNOPSIS
		Configures Windows File Explorer display and behavior options.

	.DESCRIPTION
		Reads desired registry settings from `ExplorerOptions` in Configuration.psd1 and
		applies them. Settings include file extensions visibility, hidden files, etc.
		No parameters - all settings come from the configuration.

	.EXAMPLE
		Set-ExplorerOptions
		Applies all configured Explorer options to the registry.
	#>
	Write-LogTitle "Setting File Explorer Options"

	$desiredSettings = $Configuration.ExplorerOptions
	if (-not $desiredSettings) {
		Write-LogError "Error: ExplorerOptions not found in configuration!"
		return
	}

	$allSettingsOk = $true
	foreach ($setting in $desiredSettings) {
		try {
			$currentValue = Get-ItemPropertyValue -Path $setting.Path -Name $setting.Name -ErrorAction Stop
			if ($currentValue -ne $setting.Value) {
				$allSettingsOk = $false
				break
			}
		}
		catch {
			$allSettingsOk = $false
			break
		}
	}

	if ($allSettingsOk) {
		Write-LogWarning "Explorer options already configured!"
	}
	else {
		foreach ($setting in $desiredSettings) {
			try {
				if (-not (Test-Path $setting.Path)) {
					New-Item -Path $setting.Path -Force | Out-Null
				}
				Set-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.Value -Force
			}
			catch {
				Write-LogError "Failed to set option '$($setting.Description)': $($_.Exception.Message)"
			}
		}

		Restart-Explorer

		Write-LogSuccess "Explorer options configured"
	}
}
