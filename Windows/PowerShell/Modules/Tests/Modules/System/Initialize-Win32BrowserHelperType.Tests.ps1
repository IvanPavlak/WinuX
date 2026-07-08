#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Initialize-Win32BrowserHelperType.ps1"
}

Describe "Initialize-Win32BrowserHelperType" {
	It "loads the Win32 browser helper type" {
		{ Initialize-Win32BrowserHelperType } | Should -Not -Throw
		([System.Management.Automation.PSTypeName]'Win32BrowserHelper').Type | Should -Not -BeNullOrEmpty
	}

	It "can be called repeatedly without throwing" {
		Initialize-Win32BrowserHelperType
		{ Initialize-Win32BrowserHelperType } | Should -Not -Throw
	}
}
