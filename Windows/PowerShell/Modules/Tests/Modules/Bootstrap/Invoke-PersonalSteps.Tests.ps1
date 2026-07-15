#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineType = $global:MachineType

	$BootstrapFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions"
	. "$BootstrapFunctionsPath\Invoke-PersonalSteps.ps1"
	# Dot-source the machine-scope gate so gating resolves even in sessions whose imported
	# Bootstrap module predates the Test-MachineTypeScope export.
	. "$BootstrapFunctionsPath\Test-MachineTypeScope.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineType = $script:OriginalMachineType
}

Describe "Invoke-PersonalSteps" {
	BeforeEach {
		$global:MachineType = 'Test'
		$global:Configuration = @{ BootstrapConfig = @{ PersonalSteps = @() } }

		Mock Write-Host { }
		Mock Test-AdminPrivileges { }
		Mock Write-LogTitle { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogDebug { }
		# Rename-Machine / Start-Win11Debloat are real exported commands that nothing in this
		# test file calls otherwise, so they cleanly probe which entries actually ran.
		Mock Rename-Machine { }
		Mock Start-Win11Debloat { }
	}

	It "verifies administrator privileges before running any step" {
		Invoke-PersonalSteps

		Should -Invoke Test-AdminPrivileges -Times 1 -Exactly
	}

	It "runs resolvable string entries and warns on unresolvable ones" {
		$global:Configuration.BootstrapConfig = @{ PersonalSteps = @('Rename-Machine', 'Install-MissingPersonalTool') }

		Invoke-PersonalSteps

		Should -Invoke Rename-Machine -Times 1 -Exactly
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "*Install-MissingPersonalTool*" }
	}

	It "warns and runs nothing when no personal steps are configured" {
		Invoke-PersonalSteps

		$global:Configuration = @{ BootstrapConfig = @{ } }
		Invoke-PersonalSteps

		Should -Invoke Rename-Machine -Times 0
		Should -Invoke Write-LogWarning -Times 2 -Exactly -ParameterFilter { $Message -like "*No personal steps configured*" }
		Should -Invoke Write-LogError -Times 0
	}

	It "warns when no configured step applies to the machine type" {
		$global:Configuration.ValidMachineTypes = @('PC', 'Laptop', 'Work', 'Test')
		$global:Configuration.BootstrapConfig = @{
			PersonalSteps = @(
				@{ Function = 'Rename-Machine'; Machine = 'PC/Laptop' },
				@{ Function = 'Start-Win11Debloat'; Machine = 'Work' }
			)
		}

		Invoke-PersonalSteps

		Should -Invoke Rename-Machine -Times 0
		Should -Invoke Start-Win11Debloat -Times 0
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "*No personal steps configured for this ?Test? machine*" }
	}

	It "runs hashtable entries whose Machine scope covers the machine type and skips the rest" {
		$global:Configuration.ValidMachineTypes = @('PC', 'Laptop', 'Work', 'Test')
		$global:Configuration.BootstrapConfig = @{
			PersonalSteps = @(
				@{ Function = 'Rename-Machine'; Machine = 'Test' },
				@{ Function = 'Start-Win11Debloat'; Machine = 'PC/Laptop' }
			)
		}

		Invoke-PersonalSteps

		Should -Invoke Rename-Machine -Times 1 -Exactly
		Should -Invoke Start-Win11Debloat -Times 0
		Should -Invoke Write-LogWarning -Times 0
	}

	It "reports invalid machine tokens in an entry scope and does not run the step" {
		$global:Configuration.ValidMachineTypes = @('PC', 'Laptop', 'Work', 'Test')
		$global:Configuration.BootstrapConfig = @{ PersonalSteps = @(@{ Function = 'Rename-Machine'; Machine = 'Tset' }) }

		Invoke-PersonalSteps

		Should -Invoke Rename-Machine -Times 0
		Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like "*Tset*" }
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "*No personal steps configured*" }
	}

	It "warns on an entry without a Function name" {
		$global:Configuration.BootstrapConfig = @{ PersonalSteps = @(@{ Machine = 'All' }) }

		Invoke-PersonalSteps

		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "*no Function name*" }
	}
}
