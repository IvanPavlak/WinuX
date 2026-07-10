#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Reload-WinuXModules.ps1"
}

Describe "Reload-WinuXModules" {
	BeforeEach {
		Mock Write-Host { }
		Mock Resolve-Path { [PSCustomObject]@{ Path = "C:\\Repo\\Windows\\PowerShell\\Modules" } }
		Mock Get-ChildItem { @() }
	}

	It "completes without errors when no module folders are returned" {
		{ Reload-WinuXModules } | Should -Not -Throw
		Should -Invoke Get-ChildItem -Times 1
	}
}
