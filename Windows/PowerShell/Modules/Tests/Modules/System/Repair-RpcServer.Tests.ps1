#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Test-RpcServerHealth.ps1"
	. "$FunctionsPath\Repair-RpcServer.ps1"
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

	It "tears down PowerToys processes during recovery" {
		Mock Test-RpcServerHealth { $true }
		Mock Get-Process -ParameterFilter { $Name -eq "PowerToys*" } -MockWith {
			@([PSCustomObject]@{ Id = 1234; ProcessName = "PowerToys" })
		}

		$null = Repair-RpcServer
		Should -Invoke Stop-Process -Times 1
	}

	It "removes a cached VirtualDesktop module during recovery" {
		Mock Test-RpcServerHealth { $true }
		Mock Get-Module -ParameterFilter { $Name -eq "VirtualDesktop" } -MockWith {
			[PSCustomObject]@{ Name = "VirtualDesktop" }
		}

		$null = Repair-RpcServer
		Should -Invoke Remove-Module -Times 1
	}
}
