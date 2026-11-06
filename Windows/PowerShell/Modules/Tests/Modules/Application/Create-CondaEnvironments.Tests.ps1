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
	. "$ModuleRoot\Helper\Functions\Get-ConfigSetting.ps1"

	. "$AppFunctionsPath\Create-CondaEnvironments.ps1"

	# The stand-in for conda: a function named after the full conda.exe path wins over the
	# (empty) file at that path, records every call except `env list`, answers `env list` from
	# $global:CondaStubEnvs and fails the commands $global:CondaStubFailOn matches.
	$script:CondaRoot = Join-Path $TestDrive "miniconda3"
	$script:CondaExe = Join-Path $script:CondaRoot "Scripts\conda.exe"
	New-Item -ItemType File -Path $script:CondaExe -Force | Out-Null
	Set-Item -Path "Function:global:$script:CondaExe" -Value {
		$line = "conda $($args -join ' ')"
		if ($line -eq "conda env list") {
			"# conda environments:"
			"#"
			"base                 C:\miniconda3"
			foreach ($name in $global:CondaStubEnvs) { "{0,-20} C:\miniconda3\envs\{0}" -f $name }
			$global:LASTEXITCODE = 0
			return
		}
		$global:CondaStubCalls.Add($line)
		$global:LASTEXITCODE = if ($global:CondaStubFailOn -and $line -match $global:CondaStubFailOn) { 1 } else { 0 }
	}

	$script:RepoRoot = Join-Path $TestDrive "repo"
	$script:EnvFolder = Join-Path $script:RepoRoot "Conda\Environments"
	New-Item -ItemType Directory -Path $script:EnvFolder -Force | Out-Null
	Set-Content -Path (Join-Path $script:EnvFolder "One.yml") -Value "name: One"
	Set-Content -Path (Join-Path $script:EnvFolder "Two.yml") -Value "name: Two"
	$script:OneYml = Join-Path $script:EnvFolder "One.yml"
	$script:TwoYml = Join-Path $script:EnvFolder "Two.yml"
}

AfterAll {
	Remove-Item -Path "Function:global:$script:CondaExe" -ErrorAction SilentlyContinue
	Remove-Variable -Name CondaStubCalls, CondaStubEnvs, CondaStubFailOn -Scope Global -ErrorAction SilentlyContinue
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
	$global:Configuration = $script:OriginalConfiguration
	$env:Conda = $script:OriginalConda
}

Describe "Create-CondaEnvironments" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogError { }
		Mock Write-LogWarning { }

		$env:Conda = $script:CondaRoot
		$global:MachineSpecificPaths = @{ Projects = @{ Self = @{ Root = $script:RepoRoot } } }
		$global:Configuration = @{
			BootstrapConfig = @{ DataFiles = @{ CondaEnvironments = "Conda\Environments" } }
			CondaUpdateBase = $false
		}
		$global:CondaStubCalls = [System.Collections.Generic.List[string]]::new()
		$global:CondaStubEnvs = @()
		$global:CondaStubFailOn = $null
	}

	It "returns early with a warning when Conda environment variable is not set" {
		$env:Conda = $null

		Create-CondaEnvironments

		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogError -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "Conda environment variable not set" }
		$global:CondaStubCalls.Count | Should -Be 0
	}

	It "creates every missing environment named after its file and leaves an existing one alone" {
		$global:CondaStubEnvs = @("One")

		Create-CondaEnvironments

		$global:CondaStubCalls | Should -Be @("conda env create -n Two -f $script:TwoYml")
		Should -Invoke Write-LogError -Times 0
	}

	It "takes only the named environments, in any case and with a trailing .yml" {
		Create-CondaEnvironments two.yml

		$global:CondaStubCalls | Should -Be @("conda env create -n Two -f $script:TwoYml")
	}

	It "reports a name without a file and still creates the other names" {
		Create-CondaEnvironments Missing, Two

		$global:CondaStubCalls | Should -Be @("conda env create -n Two -f $script:TwoYml")
		Should -Invoke Write-LogError -ParameterFilter { $Message -match "No environment file for \[Missing\]" }
	}

	It "removes an existing environment and creates it again with -Recreate" {
		$global:CondaStubEnvs = @("One")

		Create-CondaEnvironments One -Recreate

		$global:CondaStubCalls | Should -Be @("conda env remove -n One -y", "conda env create -n One -f $script:OneYml")
	}

	It "does not create an environment whose removal failed" {
		$global:CondaStubEnvs = @("One")
		$global:CondaStubFailOn = "env remove"

		Create-CondaEnvironments One -Recreate

		$global:CondaStubCalls | Should -Be @("conda env remove -n One -y")
		Should -Invoke Write-LogError -ParameterFilter { $Message -match "Failed to remove" }
	}

	It "updates the base environment first only when CondaUpdateBase is on" {
		Create-CondaEnvironments
		$global:CondaStubCalls | Should -Not -Contain "conda update -n base -c defaults conda -y"

		$global:CondaStubCalls.Clear()
		$global:Configuration.CondaUpdateBase = $true

		Create-CondaEnvironments

		$global:CondaStubCalls[0] | Should -Be "conda update -n base -c defaults conda -y"
	}

	It "skips the base update on a run with -Name even when CondaUpdateBase is on" {
		$global:Configuration.CondaUpdateBase = $true

		Create-CondaEnvironments One

		$global:CondaStubCalls | Should -Be @("conda env create -n One -f $script:OneYml")
	}

	It "changes nothing with -List or -DryRun" {
		$global:CondaStubEnvs = @("One")
		$global:Configuration.CondaUpdateBase = $true

		Create-CondaEnvironments -List
		Create-CondaEnvironments -Recreate -DryRun

		$global:CondaStubCalls.Count | Should -Be 0
		Should -Invoke Write-Host -ParameterFilter { "$Object" -match "One\s+exists" }
		Should -Invoke Write-Host -ParameterFilter { "$Object" -match "Two\s+missing" }
		Should -Invoke Write-Host -ParameterFilter { "$Object" -eq "  conda env remove -n One -y" }
		Should -Invoke Write-Host -ParameterFilter { "$Object" -eq "  conda env create -n Two -f $script:TwoYml" }
	}
}
