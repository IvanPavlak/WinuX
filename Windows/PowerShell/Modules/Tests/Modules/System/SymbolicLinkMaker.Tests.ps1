#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	# The unconfigured-section guards warn through Confirm-ConfigValue (Helper);
	# dot-source it (and its Test-ConfigValue dependency) so the Write-LogWarning
	# mocks in these tests apply to the guard's warning.
	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"

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
		Mock Write-LogWarning { }
	}

	It "returns with a warning when SymbolicLinks configuration is missing" {
		{ SymbolicLinkMaker } | Should -Not -Throw

		Should -Invoke DetermineMachineType -Times 1
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogError -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "SymbolicLinks not configured" }
	}

	It "returns with a warning when SymbolicLinks is an empty hashtable" {
		$script:MachineSpecificPaths = @{ SymbolicLinks = @{} }

		{ SymbolicLinkMaker } | Should -Not -Throw

		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "SymbolicLinks not configured" }
	}
}
