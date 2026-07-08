function Display-SystemLanguageSettings {
	<#
	.SYNOPSIS
		Displays the current system language, locale, and culture settings.

	.DESCRIPTION
		Prints three sections:
		- Display Language(s): output of `Get-WinUserLanguageList`
		- System Locale: output of `Get-WinSystemLocale`
		- User Culture: output of `Get-Culture`

	.EXAMPLE
		Display-SystemLanguageSettings
		Prints the current language, locale, and culture information.
	#>
	Write-LogTitle "System Language Settings"

	Write-Host -ForegroundColor DarkCyan "`n [Display Language(s)]"
	Get-WinUserLanguageList

	Write-Host -ForegroundColor DarkCyan " [System Locale]`n"
	Get-WinSystemLocale

	Write-Host -ForegroundColor DarkCyan " [User Culture]`n"
	Get-Culture
}
