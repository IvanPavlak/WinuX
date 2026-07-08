#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Reload-CustomModules.ps1"
}

Describe "Reload-CustomModules" {
	BeforeEach {
		Mock Write-Host { }
		Mock Resolve-Path { [PSCustomObject]@{ Path = "C:\\Repo\\Windows\\PowerShell\\Modules" } }
		Mock Get-ChildItem { @() }
	}

	It "completes without errors when no module folders are returned" {
		{ Reload-CustomModules } | Should -Not -Throw
		Should -Invoke Get-ChildItem -Times 1
	}
}
