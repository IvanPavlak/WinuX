#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Install-WingetApps.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
}

Describe "Install-WingetApps" {
	BeforeEach {
		Mock Write-Host { }
		Mock Test-AdminPrivileges { }
		Mock DetermineMachineType { 'Laptop' }
		Mock winget { @() }
		Mock Invoke-Expression { }

		$global:MachineSpecificPaths = @{ Projects = @{ Self = @{ Root = $TestDrive } } }
		$global:Configuration = @{ BootstrapConfig = @{ DataFiles = @{ WinGetApps = 'winget.csv' } } }
	}

	It "invokes winget install expression only for matching machine entries" {
		$csv = @'
App,Machine,Version,Scope,Interactive,Source
Git.Git,Laptop,Latest,d,n,w
XP9KHM4BK9FZ7Q,PC,Latest,d,n,s
'@
		Set-Content -Path (Join-Path $TestDrive 'winget.csv') -Value $csv

		Install-WinGetApps

		Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter { $Command -like '*winget install*Git.Git*' }
	}
}
