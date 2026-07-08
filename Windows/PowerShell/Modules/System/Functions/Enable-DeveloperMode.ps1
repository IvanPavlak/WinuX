function Enable-DeveloperMode {
	<#
	.SYNOPSIS
		Enables Windows Developer Mode.

	.DESCRIPTION
		Sets the Developer Mode registry unlock (AppModelUnlock\AllowDevelopmentWithoutDevLicense = 1),
		which allows running unsigned scripts and sideloading unpacked apps for development. The optional
		`Tools.DeveloperMode` capability (Device Portal / SSH for remote UWP debugging) is deliberately
		NOT installed: Get/Add-WindowsCapability open a DISM servicing session and hit Windows Update,
		which stalls bootstrap for minutes on fresh machines before failing. If ever needed, install it:
		Get-WindowsCapability -Online -Name "Tools.DeveloperMode*" | Add-WindowsCapability -Online
		Requires administrator privileges.

	.EXAMPLE
		Enable-DeveloperMode
		Enables Windows Developer Mode.
	#>
	Test-AdminPrivileges

	Write-LogTitle "Enabling Developer Mode"
	# Developer Mode is unlocked by this value under AppModelUnlock (NOT the AppPrivacy policy key);
	# setting it is self-contained and needs no Windows Update / component servicing.
	$appModelUnlock = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"

	$developerModeEnabled = Test-RegistryValue -Path $appModelUnlock -Name "AllowDevelopmentWithoutDevLicense" -ExpectedValue "1"

	if (-not $developerModeEnabled) {
		try {
			if (-not (Test-Path $appModelUnlock)) {
				New-Item -Path $appModelUnlock -Force | Out-Null
			}

			Set-ItemProperty -Path $appModelUnlock -Name "AllowDevelopmentWithoutDevLicense" -Value 1 -Type DWord -Force

			Write-LogSuccess "Developer Mode enabled"
		}
		catch {
			Write-LogError "Failed to enable Developer Mode: $($_.Exception.Message)"
		}
	}
	else {
		Write-LogWarning "Developer Mode already enabled"
	}
}
