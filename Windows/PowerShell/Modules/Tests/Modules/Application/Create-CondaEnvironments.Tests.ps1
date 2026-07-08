#Requires -Modules Pester

BeforeAll {
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalConda = $env:Conda

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
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

	It "returns early when Conda environment variable is not set" {
		$env:Conda = $null

		Create-CondaEnvironments

		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogError -Times 1
		Should -Invoke Write-LogWarning -Times 1
	}
}
