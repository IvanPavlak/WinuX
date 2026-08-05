#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Upgrade-All.ps1"
	# Dot-sourced so it exists to Mock regardless of what the imported module exports.
	. "$ModuleRoot\Bootstrap\Functions\Resolve-PackageManagers.ps1"

	# Function stubs standing in for the three CLIs. None of them is present on a clean CI runner,
	# and `scoop` resolves to an external script that Mock cannot bind in script scope even when it
	# is - so the suite provides its own commands to mock instead of depending on the machine.
	# Upgrade-All's Get-Command presence check sees these, which is what the tests want.
	function winget { }
	function scoop { }
	function choco { }
}

Describe "Upgrade-All" {
	BeforeEach {
		$global:Configuration = [PSCustomObject]@{
			PackageManagers = @()
		}

		Mock Test-AdminPrivileges { }
		Mock Get-PinnedApps { @() }
		Mock Show-PinnedAppsWarning { }
		Mock Sync-AppPins { }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		# The stubs set $LASTEXITCODE explicitly. A real CLI sets it; a function stub does not, so
		# without this the exit-code assertions would read whatever ambient value the previous test
		# left behind and pass or fail depending on execution order.
		Mock winget { $global:LASTEXITCODE = 0 }
		Mock scoop { $global:LASTEXITCODE = 0 }
		Mock choco { $global:LASTEXITCODE = 0 }
		Mock Resolve-PackageManagers { @() }
	}

	It "does nothing when no package managers are in play" {
		{ Upgrade-All } | Should -Not -Throw

		Should -Invoke Test-AdminPrivileges -Times 1
		Should -Invoke Get-PinnedApps -Times 0
		Should -Invoke winget -Times 0
	}

	It "upgrades only the managers Resolve-PackageManagers returns" {
		Mock Resolve-PackageManagers { @('WinGet') }

		Upgrade-All

		Should -Invoke winget -ParameterFilter { $args -contains 'upgrade' } -Times 1 -Exactly
		Should -Invoke choco -Times 0
		Should -Invoke scoop -Times 0
	}

	It "passes an explicit -PackageManager through to the resolver" {
		Mock Resolve-PackageManagers { @('Chocolatey') } -ParameterFilter { $PackageManager -contains 'Chocolatey' }

		Upgrade-All -PackageManager 'Chocolatey'

		Should -Invoke choco -ParameterFilter { $args -contains 'upgrade' } -Times 1 -Exactly
		Should -Invoke winget -Times 0
	}

	It "accepts more than one manager" {
		Mock Resolve-PackageManagers { @('WinGet', 'Chocolatey') }

		Upgrade-All -PackageManager @('WinGet', 'Chocolatey')

		Should -Invoke winget -ParameterFilter { $args -contains 'upgrade' } -Times 1 -Exactly
		Should -Invoke choco -ParameterFilter { $args -contains 'upgrade' } -Times 1 -Exactly
	}

	It "reconciles pins before upgrading, for every manager alike" -ForEach @(
		@{ Manager = 'WinGet' }
		@{ Manager = 'Scoop' }
		@{ Manager = 'Chocolatey' }
	) {
		$expected = $Manager
		Mock Resolve-PackageManagers { @($expected) }

		Upgrade-All

		Should -Invoke Sync-AppPins -ParameterFilter { $PackageManager -eq $expected } -Times 1 -Exactly
	}

	It "skips a manager whose CLI is not installed instead of failing on it" {
		Mock Resolve-PackageManagers { @('Chocolatey') }
		Mock Get-Command { $null } -ParameterFilter { $Name -eq 'choco' }

		Upgrade-All

		Should -Invoke choco -Times 0
		Should -Invoke Write-LogError -Times 0
	}

	It "runs the plain bulk update for Scoop and leaves pin handling to Sync-AppPins" {
		Mock Resolve-PackageManagers { @('Scoop') }

		Upgrade-All

		# No app-list juggling any more: the hold recorded by Sync-AppPins is what makes
		# `scoop update *` skip a pinned app, so the pin holds for a hand-run update too.
		Should -Invoke scoop -ParameterFilter { $args -contains 'update' -and $args -contains '*' } -Times 1 -Exactly
		Should -Invoke scoop -ParameterFilter { $args -contains 'export' } -Times 0
		Should -Invoke Get-PinnedApps -Times 0
	}

	It "reports success on a zero exit code" {
		Mock Resolve-PackageManagers { @('Scoop') }

		Upgrade-All

		Should -Invoke Write-LogSuccess -Times 1 -Exactly
		Should -Invoke Write-LogError -Times 0
	}

	It "reports the failing exit code when a manager's upgrade fails" {
		Mock Resolve-PackageManagers { @('Scoop') }
		Mock scoop { $global:LASTEXITCODE = 3 }

		Upgrade-All

		Should -Invoke Write-LogError -Times 1 -Exactly
		Should -Invoke Write-LogSuccess -Times 0
	}

	It "does not carry one manager's failure over to the next" {
		Mock Resolve-PackageManagers { @('WinGet', 'Scoop') }
		Mock winget { $global:LASTEXITCODE = 3 }

		Upgrade-All

		# WinGet failed, Scoop succeeded - the per-iteration reset is what keeps Scoop from
		# inheriting WinGet's exit code.
		Should -Invoke Write-LogError -Times 1 -Exactly
		Should -Invoke Write-LogSuccess -Times 1 -Exactly
	}
}
