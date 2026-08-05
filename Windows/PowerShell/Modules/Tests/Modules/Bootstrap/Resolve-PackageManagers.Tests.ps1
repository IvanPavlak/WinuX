#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineType = $global:MachineType

	$ModuleRoot = (Get-RepositoryPath).Modules
	$BootstrapFunctionsPath = Join-Path $ModuleRoot "Bootstrap\Functions"

	. "$BootstrapFunctionsPath\Resolve-PackageManagers.ps1"
	# Dot-sourced so they exist to Mock regardless of what the imported module exports.
	. "$BootstrapFunctionsPath\Import-AppCsv.ps1"
	. "$BootstrapFunctionsPath\Test-MachineTypeScope.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineType = $script:OriginalMachineType
}

Describe "Resolve-PackageManagers" {
	BeforeEach {
		$global:MachineType = 'Test'
		$global:Configuration = @{
			PackageManagers   = @('WinGet', 'Scoop', 'Chocolatey')
			ValidMachineTypes = @('Test')
		}

		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogDebug { }

		# Every list holds one All-scoped app unless a test overrides this.
		Mock Import-AppCsv { @([pscustomobject]@{ App = 'Some.App'; Machine = 'All' }) }
	}

	It "returns every configured manager whose app list has entries" {
		Resolve-PackageManagers | Should -Be @('WinGet', 'Scoop', 'Chocolatey')
	}

	It "returns canonical order and spelling regardless of how the configuration lists them" {
		$global:Configuration.PackageManagers = @('chocolatey', 'winget')

		Resolve-PackageManagers | Should -Be @('WinGet', 'Chocolatey')
	}

	It "drops a manager that is not in PackageManagers" {
		$global:Configuration.PackageManagers = @('WinGet')

		Resolve-PackageManagers | Should -Be @('WinGet')
	}

	It "drops a configured manager whose app list is empty and says so" {
		Mock Import-AppCsv -ParameterFilter { $DataFileKey -eq 'ScoopApps' } -MockWith { @() }

		Resolve-PackageManagers | Should -Be @('WinGet', 'Chocolatey')
		Should -Invoke Write-LogWarning -Times 1 -Exactly
	}

	It "drops a configured manager whose only apps target another machine type" {
		$global:Configuration.ValidMachineTypes = @('Test', 'PC')
		Mock Import-AppCsv -ParameterFilter { $DataFileKey -eq 'ChocolateyApps' } -MockWith {
			@([pscustomobject]@{ App = 'Other.App'; Machine = 'PC' })
		}

		Resolve-PackageManagers | Should -Be @('WinGet', 'Scoop')
	}

	It "returns nothing and warns when PackageManagers is empty" {
		$global:Configuration.PackageManagers = @()

		@(Resolve-PackageManagers).Count | Should -Be 0
		Should -Invoke Write-LogWarning -Times 1 -Exactly
		Should -Invoke Import-AppCsv -Times 0
	}

	It "reports an unknown entry instead of silently ignoring it" {
		$global:Configuration.PackageManagers = @('WinGet', 'Chocolatley')

		Resolve-PackageManagers | Should -Be @('WinGet')
		Should -Invoke Write-LogError -Times 1 -Exactly
	}

	It "honours an explicit request without consulting configuration or the app lists" {
		$global:Configuration.PackageManagers = @('WinGet')

		Resolve-PackageManagers -PackageManager 'Chocolatey' | Should -Be @('Chocolatey')
		Should -Invoke Import-AppCsv -Times 0
	}

	It "returns an explicit multi-manager request in canonical order" {
		Resolve-PackageManagers -PackageManager @('Chocolatey', 'WinGet') | Should -Be @('WinGet', 'Chocolatey')
	}
}
