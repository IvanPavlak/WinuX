#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Display-SystemLanguageSettings.ps1"
}

Describe "Display-SystemLanguageSettings" {
	BeforeEach {
		Mock Write-Host { }
		Mock Get-WinUserLanguageList { @("en-US") }
		Mock Get-WinSystemLocale { [PSCustomObject]@{ Name = "en-US" } }
		Mock Get-Culture { [PSCustomObject]@{ Name = "en-US" } }
	}

	It "queries language, locale, and culture providers" {
		{ Display-SystemLanguageSettings } | Should -Not -Throw
		Should -Invoke Get-WinUserLanguageList -Times 1
		Should -Invoke Get-WinSystemLocale -Times 1
		Should -Invoke Get-Culture -Times 1
	}
}
