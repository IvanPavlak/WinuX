#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Determine-DotnetDependencies.ps1"
}

Describe "Determine-DotnetDependencies" {
	BeforeEach {
		Mock Test-Path { $false }
		Mock Write-Host { }
		Mock Write-LogError { }
	}

	It "returns when the provided search path does not exist" {
		{ Determine-DotnetDependencies -SearchPath "C:\\Missing" } | Should -Not -Throw
		Should -Invoke Test-Path -Times 1 -ParameterFilter { $Path -eq "C:\\Missing" }
		Should -Invoke Write-LogError -Times 1
	}
}
