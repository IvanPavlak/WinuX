#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Window\Functions"
	. "$FunctionsPath\Get-WindowDisplayName.ps1"
}

Describe "Get-WindowDisplayName" {
	It "maps WindowsTerminal to the friendly product name" {
		Get-WindowDisplayName -ProcessName "WindowsTerminal" -Title "PowerShell" | Should -Be "Windows Terminal"
	}

	It "ignores the title for a mapped process" {
		Get-WindowDisplayName -ProcessName "WindowsTerminal" -Title "anything" | Should -Be "Windows Terminal"
	}

	It "falls back to the window title for unmapped processes" {
		Get-WindowDisplayName -ProcessName "chrome" -Title "GitHub - Google Chrome" | Should -Be "GitHub - Google Chrome"
	}

	It "returns an empty string when an unmapped process has an empty title" {
		Get-WindowDisplayName -ProcessName "chrome" -Title "" | Should -Be ""
	}
}
