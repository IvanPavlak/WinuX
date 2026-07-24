#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Test-RpcServerHealth.ps1"
	. "$FunctionsPath\Repair-RpcServer.ps1"

	# Cross-module recovery helper (Window module) stubbed so it can be mocked
	# (no-op where the real module is loaded).
	if (-not (Get-Command Reset-VirtualDesktopState -ErrorAction SilentlyContinue)) {
		function Reset-VirtualDesktopState { }
	}
}

Describe "Repair-RpcServer" {
	BeforeEach {
		Mock Write-Host { }
		Mock Get-Process { $null }
		Mock Stop-Process { }
		Mock Get-Module { $null }
		Mock Remove-Module { }
		Mock Start-Sleep { }
		Mock Restart-Service { }
		Mock Reset-VirtualDesktopState { $true }
	}

	It "returns true when post-recovery probe reports healthy" {
		Mock Test-RpcServerHealth { $true }

		$result = Repair-RpcServer
		$result | Should -BeTrue
	}

	It "returns false when post-recovery probe still fails" {
		Mock Test-RpcServerHealth { $false }

		$result = Repair-RpcServer
		$result | Should -BeFalse
	}

	It "reconnects the session's VirtualDesktop state as the primary recovery step" {
		Mock Test-RpcServerHealth { $true }

		$null = Repair-RpcServer

		Should -Invoke Reset-VirtualDesktopState -Times 1 -Exactly
		Should -Invoke Remove-Module -Times 0
	}

	It "does not terminate PowerToys on the first attempt" {
		Mock Test-RpcServerHealth { $true }
		Mock Get-Process -ParameterFilter { $Name -eq "PowerToys*" } -MockWith {
			@([PSCustomObject]@{ Id = 1234; ProcessName = "PowerToys" })
		}

		# The session-side reset already recovered attempt 1 - PowerToys must not be
		# collateral damage of a failure it did not cause.
		$null = Repair-RpcServer
		Should -Invoke Stop-Process -Times 0
	}

	It "escalates to terminating PowerToys from the second attempt on" {
		Mock Test-RpcServerHealth { $false }
		Mock Get-Process -ParameterFilter { $Name -eq "PowerToys*" } -MockWith {
			@([PSCustomObject]@{ Id = 1234; ProcessName = "PowerToys" })
		}

		$null = Repair-RpcServer -MaxAttempts 2
		Should -Invoke Stop-Process -Times 1
	}

	It "falls back to unloading the cached VirtualDesktop module when the reset helper is unavailable" {
		Mock Test-RpcServerHealth { $true }
		Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Reset-VirtualDesktopState' }
		Mock Get-Module -ParameterFilter { $Name -eq "VirtualDesktop" } -MockWith {
			[PSCustomObject]@{ Name = "VirtualDesktop" }
		}

		$null = Repair-RpcServer
		Should -Invoke Remove-Module -Times 1
	}
}
