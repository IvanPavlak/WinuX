#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\SymbolicLinkMaker.ps1"
}

Describe "SymbolicLinkMaker" {
	BeforeEach {
		$script:MachineSpecificPaths = @{}

		Mock Test-AdminPrivileges { }
		Mock DetermineMachineType { "PC" }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogError { }
	}

	It "returns when SymbolicLinks configuration is missing" {
		{ SymbolicLinkMaker } | Should -Not -Throw

		Should -Invoke DetermineMachineType -Times 1
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogError -Times 1
	}
}
