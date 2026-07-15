#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Install-ChocolateyApps.ps1"
	# Dot-source the machine-scope gate so the Machine-column filtering resolves even in
	# sessions whose imported Bootstrap module predates the Test-MachineTypeScope export.
	. (Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions\Test-MachineTypeScope.ps1")
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
}

Describe "Install-ChocolateyApps" {
	BeforeEach {
		Mock Write-Host { }
		Mock Test-AdminPrivileges { }
		Mock DetermineMachineType { 'Laptop' }
		Mock choco { }

		$global:MachineSpecificPaths = @{ Projects = @{ Self = @{ Root = $TestDrive } } }
		$global:Configuration = @{ BootstrapConfig = @{ DataFiles = @{ ChocolateyApps = 'choco.csv' } } }
	}

	It "installs only entries matching machine type or All" {
		$csv = @'
App,Machine,Params,Version,Force
git,All,,,
vlc,Laptop,,,
paint,PC,,,
'@
		Set-Content -Path (Join-Path $TestDrive 'choco.csv') -Value $csv

		Install-ChocolateyApps

		Should -Invoke choco -Times 2 -Exactly
	}
}
