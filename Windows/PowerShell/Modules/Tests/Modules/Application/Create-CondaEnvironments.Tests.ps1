#Requires -Modules Pester

BeforeAll {
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalConda = $env:Conda

	$ModuleRoot = (Get-RepositoryPath).Modules
	$AppFunctionsPath = Join-Path $ModuleRoot "Application\Functions"

	# The unconfigured-section guards warn through Confirm-ConfigValue (Helper);
	# dot-source it (and its Test-ConfigValue dependency) so the Write-LogWarning
	# mocks in these tests apply to the guard's warning.
	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"

	. "$AppFunctionsPath\Create-CondaEnvironments.ps1"
}

AfterAll {
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
	$global:Configuration = $script:OriginalConfiguration
	$env:Conda = $script:OriginalConda
}

Describe "Create-CondaEnvironments" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogError { }
		Mock Write-LogWarning { }
	}

	It "returns early with a warning when Conda environment variable is not set" {
		$env:Conda = $null

		Create-CondaEnvironments

		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogError -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "Conda environment variable not set" }
	}
}
