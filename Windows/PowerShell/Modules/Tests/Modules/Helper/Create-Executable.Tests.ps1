#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Create-Executable.ps1"
}

Describe "Create-Executable" {
	BeforeEach {
		Mock Write-Host { }
		Mock Get-Module { $null }
	}

	It "returns when ps2exe module is not available" {
		{ Create-Executable -FunctionName "Any-Function" } | Should -Not -Throw
		Should -Invoke Get-Module -Times 1 -ParameterFilter { $ListAvailable -and $Name -eq "ps2exe" }
	}
}
