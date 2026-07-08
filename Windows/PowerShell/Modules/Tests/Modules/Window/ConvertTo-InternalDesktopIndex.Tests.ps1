#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\ConvertTo-InternalDesktopIndex.ps1"
}

Describe "ConvertTo-InternalDesktopIndex" {
	It "converts a 1-based desktop number to a 0-based index" {
		ConvertTo-InternalDesktopIndex -DesktopNumber 1 | Should -Be 0
		ConvertTo-InternalDesktopIndex -DesktopNumber 3 | Should -Be 2
	}

	It "applies the desktop offset for alongside workspaces" {
		ConvertTo-InternalDesktopIndex -DesktopNumber 1 -DesktopOffset 2 | Should -Be 2
		ConvertTo-InternalDesktopIndex -DesktopNumber 2 -DesktopOffset 2 | Should -Be 3
	}

	It "defaults the offset to zero" {
		ConvertTo-InternalDesktopIndex -DesktopNumber 4 | Should -Be 3
	}

	It "returns an integer" {
		(ConvertTo-InternalDesktopIndex -DesktopNumber 1) | Should -BeOfType [int]
	}
}
