#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Install-ScoopApps.ps1"
	# Dot-source the machine-scope gate so the Machine-column filtering resolves even in
	# sessions whose imported Bootstrap module predates the Test-MachineTypeScope export.
	. (Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions\Test-MachineTypeScope.ps1")
	# Same reason for the layered CSV reader the installer now reads through.
	. (Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions\Import-AppCsv.ps1")

	# Dot-sourced so it exists to Mock: `scoop export` goes through it, so the tests never depend on
	# scoop being installed on the machine running them.
	. (Join-Path (Get-RepositoryPath).Modules "System\Functions\Invoke-PackageManagerCommand.ps1")
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
}

Describe "Install-ScoopApps" {
	BeforeEach {
		Mock Write-Host { }
		Mock Test-AdminPrivileges { }
		Mock DetermineMachineType { 'Laptop' }
		Mock Invoke-Expression { }
		Mock Write-LogWarning { }
		Mock Invoke-PackageManagerCommand { throw 'scoop export unavailable (test stub)' }

		$global:MachineSpecificPaths = @{ Projects = @{ Self = @{ Root = $TestDrive } } }
		$global:Configuration = @{ BootstrapConfig = @{ DataFiles = @{ ScoopApps = 'scoop.csv' } } }
	}

	It "installs machine-matching app entries when installed-app export is unavailable" {
		$csv = @'
App,Machine,Global,Version
git,Laptop,false,latest
paint,PC,false,latest
'@
		Set-Content -Path (Join-Path $TestDrive 'scoop.csv') -Value $csv

		Install-ScoopApps

		Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter { $Command -like 'scoop install git*' }
	}

	It "reads the installed apps through scoop export and updates an installed app instead of installing it" {
		Mock Invoke-PackageManagerCommand { '{"apps":[', '{"Name":"git","Info":""}', ']}' } -ParameterFilter { $PackageManager -eq 'Scoop' -and $Arguments[0] -eq 'export' }
		$csv = @'
App,Machine,Global,Version
git,Laptop,false,latest
'@
		Set-Content -Path (Join-Path $TestDrive 'scoop.csv') -Value $csv

		Install-ScoopApps

		Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter { $Command -like 'scoop update git*' }
		Should -Invoke Invoke-Expression -Times 0 -ParameterFilter { $Command -like 'scoop install*' }
	}
}
