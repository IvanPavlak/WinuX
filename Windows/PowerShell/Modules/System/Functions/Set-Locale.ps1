function Set-Locale {
	<#
    .SYNOPSIS
        Sets the system locale.

    .DESCRIPTION
        Reads available locales from `Locales` in Configuration.psd1. When called with a
        locale name, sets that locale. When called without arguments, shows an interactive
        menu of available locales.
        Requires administrator privileges.

    .PARAMETER Locale
        Locale name as defined in Configuration.psd1 (e.g. "en-US", "hr-HR").
        Omit to show the interactive menu.

    .EXAMPLE
        Set-Locale
        Shows the locale selection menu.

    .EXAMPLE
        Set-Locale -Locale "en-US"
        Sets the system locale to en-US.
    #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[string]$Locale
	)

	Test-AdminPrivileges

	$localeOptions = $Configuration.Locales.Keys
	$defaultLocaleName = $Configuration.DefaultLocale
	$targetLocaleName = ""

	if (-not [string]::IsNullOrWhiteSpace($Locale)) {
		if ($localeOptions -contains $Locale) {
			$targetLocaleName = $Locale
		}
		else {
			Write-LogError "Error: Locale [$Locale] not found in the list of configured locales!"
			return
		}
	}
 else {
		$resolveParams = @{
			OptionList               = $localeOptions
			MenuTitle                = "[Available Locales]"
			PromptMessage            = "Select a locale (or press Enter for default [$defaultLocaleName])"
			AllowEmptyPromptResponse = $true
		}

		$selectedLocaleName = Resolve-Selection @resolveParams

		if ([string]::IsNullOrWhiteSpace($selectedLocaleName)) {
			$targetLocaleName = $defaultLocaleName
		}
		else {
			$targetLocaleName = $selectedLocaleName
		}
	}

	$localeConfig = $Configuration.Locales[$targetLocaleName]
	$targetLocale = $localeConfig.Code
	$targetGeoId = $localeConfig.GeoId

	Write-LogTitle "Setting User Culture to $targetLocaleName ($targetLocale)"

	$currentCulture = (Get-Culture).Name

	if ($currentCulture -eq $targetLocale) {
		Write-LogWarning "User culture already set to [$targetLocaleName]"
	}
	else {
		try {
			# Set-WinSystemLocale -SystemLocale $targetLocale

			Set-Culture -CultureInfo $targetLocale
			Write-LogSuccess "Culture set to [$targetLocale]"

			#if (Get-Command -Name Set-WinUILanguageOverride -ErrorAction SilentlyContinue) {
			#	Set-WinUILanguageOverride -Language $targetLocale
			#}

			try {
				Set-WinHomeLocation -GeoId $targetGeoId
				Write-LogSuccess "Home location GeoID set to $targetGeoId ($targetLocaleName)"
			}
			catch {
				Write-LogWarning "Could not set home location via cmdlet: $_"

				try {
					Set-ItemProperty -Path "HKCU:\Control Panel\International\Geo" -Name "Nation" -Value $targetGeoId -Type DWord -Force
					Write-LogSuccess "Home location set via registry"
				}
				catch {
					Write-LogWarning "Could not set home location via registry: $_"
				}
			}

			$verifyCulture = (Get-Culture).Name
			if ($verifyCulture -eq $targetLocale) {
				Write-LogSuccess "User culture successfully set to $targetLocaleName"
				Write-LogWarning "Some settings may require a system restart to take full effect"
			}
			else {
				Write-LogWarning "User culture was attempted to be set but verification failed"
				Write-LogWarning "Current culture reported as: $verifyCulture"
			}
		}
		catch {
			Write-LogError "An error occurred while setting user culture: $_"
		}
	}
}
