#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineType = $global:MachineType

	$BootstrapFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions"
	. "$BootstrapFunctionsPath\Test-MachineTypeScope.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineType = $script:OriginalMachineType
}

Describe "Test-MachineTypeScope" {
	BeforeEach {
		$global:Configuration = @{ ValidMachineTypes = @('PC', 'Laptop', 'Work', 'Test') }
		Mock Write-Host { }
		Mock Write-LogError { }
	}

	It "matches every machine type when the scope is All" {
		Test-MachineTypeScope -Scope 'All' -MachineType 'Work' | Should -BeTrue
		Should -Invoke Write-LogError -Times 0
	}

	It "matches when a multi-token scope contains the machine type" {
		Test-MachineTypeScope -Scope 'PC/Laptop' -MachineType 'Laptop' | Should -BeTrue
		Should -Invoke Write-LogError -Times 0
	}

	It "matches case-insensitively for both tokens and the wildcard" {
		Test-MachineTypeScope -Scope 'laptop' -MachineType 'Laptop' | Should -BeTrue
		Test-MachineTypeScope -Scope 'all' -MachineType 'Work' | Should -BeTrue
		Should -Invoke Write-LogError -Times 0
	}

	It "does not match a valid scope naming other machine types, without reporting errors" {
		Test-MachineTypeScope -Scope 'PC/Work' -MachineType 'Laptop' | Should -BeFalse
		Should -Invoke Write-LogError -Times 0
	}

	It "reports an unknown token and returns false" {
		Test-MachineTypeScope -Scope 'Labtop' -MachineType 'Laptop' -Context 'WinGetApps.csv [MyApp]' | Should -BeFalse
		Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like '*Labtop*' -and $Message -like '*WinGetApps.csv ?MyApp?*' }
	}

	It "still matches on the valid tokens while reporting the unknown ones" {
		Test-MachineTypeScope -Scope 'Labtop/Laptop' -MachineType 'Laptop' | Should -BeTrue
		Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like '*Labtop*' }
	}

	It "reports a blank scope and never matches it" {
		Test-MachineTypeScope -Scope '' -MachineType 'Laptop' | Should -BeFalse
		Test-MachineTypeScope -Scope '  /  ' -MachineType 'Laptop' | Should -BeFalse
		Should -Invoke Write-LogError -Times 2 -Exactly
	}

	It "skips token validation when the configuration has no ValidMachineTypes" {
		$global:Configuration = @{ }

		Test-MachineTypeScope -Scope 'PC' -MachineType 'PC' | Should -BeTrue
		Test-MachineTypeScope -Scope 'Labtop' -MachineType 'Laptop' | Should -BeFalse
		Should -Invoke Write-LogError -Times 0
	}

	It "defaults the machine type to the global machine type" {
		$global:MachineType = 'Work'

		Test-MachineTypeScope -Scope 'Work' | Should -BeTrue
		Test-MachineTypeScope -Scope 'PC' | Should -BeFalse
	}

	It "matches only All when the machine type is empty" {
		Test-MachineTypeScope -Scope 'All' -MachineType '' | Should -BeTrue
		Test-MachineTypeScope -Scope 'PC' -MachineType '' | Should -BeFalse
	}
}
