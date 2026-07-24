#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Test-RpcServerHealth.ps1"

	# Cross-module probe helper (Window module) stubbed so it can be mocked
	# (no-op where the real module is loaded).
	if (-not (Get-Command Test-VirtualDesktopComHealth -ErrorAction SilentlyContinue)) {
		function Test-VirtualDesktopComHealth { param([int]$TimeoutMs) }
	}
}

Describe "Test-RpcServerHealth" {
	BeforeEach {
		Mock Write-Host { }
	}

	It "returns false when any required service is not running" {
		Mock Get-Service {
			if ($Name -eq "RpcSs") {
				[PSCustomObject]@{ Status = "Stopped" }
			}
			else {
				[PSCustomObject]@{ Status = "Running" }
			}
		}

		$result = Test-RpcServerHealth -ServiceNames @("RpcSs", "DcomLaunch")
		$result | Should -BeFalse
	}

	It "returns true when all required services are running" {
		Mock Get-Service { [PSCustomObject]@{ Status = "Running" } }

		$result = Test-RpcServerHealth -ServiceNames @("RpcSs", "DcomLaunch", "RpcEptMapper")
		$result | Should -BeTrue
	}

	It "returns true when the live probe reports the session healthy" {
		Mock Get-Service { [PSCustomObject]@{ Status = "Running" } }
		Mock Test-VirtualDesktopComHealth { [PSCustomObject]@{ Healthy = $true; TimedOut = $false; Error = $null } }

		$result = Test-RpcServerHealth -ServiceNames @("RpcSs") -Probe
		$result | Should -BeTrue
	}

	It "passes the probe timeout through to the in-process probe" {
		Mock Get-Service { [PSCustomObject]@{ Status = "Running" } }
		Mock Test-VirtualDesktopComHealth { [PSCustomObject]@{ Healthy = $true; TimedOut = $false; Error = $null } }

		$null = Test-RpcServerHealth -ServiceNames @("RpcSs") -Probe -ProbeTimeoutMs 1234

		Should -Invoke Test-VirtualDesktopComHealth -Times 1 -Exactly -ParameterFilter { $TimeoutMs -eq 1234 }
	}

	It "returns false when the live probe reports RPC unavailable" {
		Mock Get-Service { [PSCustomObject]@{ Status = "Running" } }
		Mock Test-VirtualDesktopComHealth {
			[PSCustomObject]@{ Healthy = $false; TimedOut = $false; Error = "The RPC server is unavailable. (0x800706BA) (HRESULT 0x800706BA)" }
		}

		$result = Test-RpcServerHealth -ServiceNames @("RpcSs") -Probe
		$result | Should -BeFalse
	}

	It "returns false when the live probe times out" {
		Mock Get-Service { [PSCustomObject]@{ Status = "Running" } }
		Mock Test-VirtualDesktopComHealth {
			[PSCustomObject]@{ Healthy = $false; TimedOut = $true; Error = "probe timed out after 100ms" }
		}

		$result = Test-RpcServerHealth -ServiceNames @("RpcSs") -Probe -ProbeTimeoutMs 100
		$result | Should -BeFalse
	}

	It "treats a non-RPC probe failure as healthy" {
		Mock Get-Service { [PSCustomObject]@{ Status = "Running" } }
		Mock Test-VirtualDesktopComHealth {
			[PSCustomObject]@{ Healthy = $false; TimedOut = $false; Error = "The specified module 'VirtualDesktop' was not loaded" }
		}

		# A missing module is not an RPC outage - recovery must not be triggered.
		$result = Test-RpcServerHealth -ServiceNames @("RpcSs") -Probe
		$result | Should -BeTrue
	}

	It "falls back to service status when the probe helper is unavailable" {
		Mock Get-Service { [PSCustomObject]@{ Status = "Running" } }
		Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Test-VirtualDesktopComHealth' }

		$result = Test-RpcServerHealth -ServiceNames @("RpcSs") -Probe
		$result | Should -BeTrue
	}
}
