function Set-DisplayLanguage {
	<#
    .SYNOPSIS
        Sets the Windows display language.

    .DESCRIPTION
        Reads available display languages from `DisplayLanguages` in Configuration.psd1 (a map of
        friendly name to language tag, e.g. "English (US)" = "en-US").
        When called with a language name (a `DisplayLanguages` key), sets that display language.
        When called without arguments, shows an interactive menu of available languages; Enter
        selects `DefaultDisplayLanguage`.
        Moves the language tag to the front of the Windows user language list (adding it when it
        is not installed) and verifies the result; a sign-out is needed for it to take full effect.
        Requires administrator privileges.

    .PARAMETER Language
        Language name as defined in `DisplayLanguages` in Configuration.psd1 (the key, e.g.
        "English (US)", not the tag "en-US"). Omit to show the interactive menu.

    .EXAMPLE
        Set-DisplayLanguage
        Shows the display language selection menu.

    .EXAMPLE
        Set-DisplayLanguage -Language "English (US)"
        Sets the display language to the tag configured for "English (US)" (e.g. en-US).
    #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[string]$Language
	)

	Test-AdminPrivileges

	$displayLanguages = Get-ConfigSetting -Path 'DisplayLanguages'
	if (-not (Confirm-ConfigValue $displayLanguages "DisplayLanguages not configured - leaving display language as-is!")) {
		return
	}

	$languageOptions = $displayLanguages.Keys
	$defaultLanguageName = Get-ConfigSetting -Path 'DefaultDisplayLanguage'
	$targetLanguageName = ""

	if (-not [string]::IsNullOrWhiteSpace($Language)) {
		if ($languageOptions -contains $Language) {
			$targetLanguageName = $Language
		}
		else {
			Write-LogError "Display Language [$Language] not found in configuration!"
			return
		}
	}
 else {
		$resolveParams = @{
			OptionList               = $languageOptions
			MenuTitle                = "[Available Display Languages]"
			PromptMessage            = "Select a display language (or press Enter for default [$defaultLanguageName])"
			AllowEmptyPromptResponse = $true
		}

		$selectedLanguageName = Resolve-Selection @resolveParams

		if ([string]::IsNullOrWhiteSpace($selectedLanguageName)) {
			$targetLanguageName = $defaultLanguageName
		}
		else {
			$targetLanguageName = $selectedLanguageName
		}
	}

	$targetLanguage = $displayLanguages[$targetLanguageName]

	Write-LogTitle "Setting Windows Display Language to [$targetLanguage]"

	$currentLanguageList = Get-WinUserLanguageList

	if ($currentLanguageList[0].LanguageTag -eq $targetLanguage) {
		Write-LogWarning "Display language already set to [$targetLanguageName]!"
	}
	else {
		try {
			if (-not ($currentLanguageList | Where-Object { $_.LanguageTag -eq $targetLanguage })) {
				Write-LogWarning "Language [$targetLanguageName] is not installed. Adding it to the list!"
				$currentLanguageList.Add($targetLanguage)
			}

			$languageObject = $currentLanguageList | Where-Object { $_.LanguageTag -eq $targetLanguage }
			$currentLanguageList.Remove($languageObject)
			$currentLanguageList.Insert(0, $languageObject)

			Set-WinUserLanguageList -LanguageList $currentLanguageList -Force -WarningAction SilentlyContinue

			$verifyLanguageList = Get-WinUserLanguageList
			if ($verifyLanguageList[0].LanguageTag -eq $targetLanguage) {
				Write-LogSuccess "Display language successfully set to [$targetLanguageName]!"
				Write-LogWarning "You must sign out and back in for this change to take full effect!"
			}
			else {
				Write-LogError "Display language was attempted to be set but verification failed!"
			}
		}
		catch {
			Write-LogError "An error occurred while setting display language: $($_.Exception.Message)"
		}
	}
}
