#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Get-FancyZonesLayoutsPath" {
	It "Should resolve the repository custom-layouts.json by default" {
		$path = Get-FancyZonesLayoutsPath

		$path | Should -Match '\\Windows\\FancyZones\\custom-layouts\.json$'
		Test-Path $path | Should -BeTrue
	}

	It "Should resolve layout-hotkeys.json when requested" {
		$path = Get-FancyZonesLayoutsPath -File LayoutHotkeys

		$path | Should -Match '\\Windows\\FancyZones\\layout-hotkeys\.json$'
		Test-Path $path | Should -BeTrue
	}

	It "Should anchor both files in the same directory" {
		$layoutsDir = Split-Path (Get-FancyZonesLayoutsPath) -Parent
		$hotkeysDir = Split-Path (Get-FancyZonesLayoutsPath -File LayoutHotkeys) -Parent

		$layoutsDir | Should -Be $hotkeysDir
	}
}
