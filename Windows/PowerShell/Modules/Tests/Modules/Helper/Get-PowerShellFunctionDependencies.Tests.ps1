#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Get-PowerShellFunctionDependencies.ps1"
}

Describe "Get-PowerShellFunctionDependencies" {
	BeforeEach {
		$script:ProcessedFunctions = @()
		Mock Get-Command { throw "Missing" }
		Mock Write-Warning { }
	}

	It "returns null and warns when function is not found" {
		$result = Get-PowerShellFunctionDependencies -FunctionName "Not-There"

		$result | Should -Be $null
		Should -Invoke Write-Warning -Times 1
	}
}
