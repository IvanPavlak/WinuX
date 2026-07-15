#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Install-ScoopApps.ps1"
	# Dot-source the machine-scope gate so the Machine-column filtering resolves even in
	# sessions whose imported Bootstrap module predates the Test-MachineTypeScope export.
	. (Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions\Test-MachineTypeScope.ps1")

	# scoop is absent on clean CI runners; a throwing stub makes 'scoop export' fail
	# deterministically without Mock scoop (which would require scoop to pre-exist).
	function scoop { throw 'scoop export unavailable (test stub)' }
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
}
