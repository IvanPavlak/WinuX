#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Get-RpcRetryPolicy.ps1"
}

Describe "Get-RpcRetryPolicy" {
	Context "Retry policy output" {
		It "Returns provided retry values when preflight commands are unavailable" {
			Mock Get-Command { $null }

			$result = Get-RpcRetryPolicy -MaxAttempts 5 -InitialDelayMs 350

			$result.MaxAttempts | Should -Be 5
			$result.InitialDelayMs | Should -Be 350
		}

		It "Clamps retry values to at least 1" {
			Mock Get-Command { $null }

			$result = Get-RpcRetryPolicy -MaxAttempts 0 -InitialDelayMs 0

			$result.MaxAttempts | Should -Be 1
			$result.InitialDelayMs | Should -Be 1
		}
	}

	Context "RPC preflight behavior" {
		BeforeEach {
			Mock Get-Command {
				if ($Name -eq 'Test-RpcServerHealth' -or $Name -eq 'Repair-RpcServer') {
					return @{ Name = $Name }
				}
				return $null
			}
		}

		It "Uses Test-RpcServerHealth -Probe when Probe is requested" {
			Mock Test-RpcServerHealth { $true }
			Mock Repair-RpcServer { $true }

			$null = Get-RpcRetryPolicy -Probe

			Assert-MockCalled Test-RpcServerHealth -Times 1 -Exactly -ParameterFilter { $Probe }
			Assert-MockCalled Repair-RpcServer -Times 0
		}

		It "Does not call Repair-RpcServer when RPC services are healthy" {
			Mock Test-RpcServerHealth { $true }
			Mock Repair-RpcServer { $true }

			$null = Get-RpcRetryPolicy

			Assert-MockCalled Test-RpcServerHealth -Times 1 -Exactly
			Assert-MockCalled Repair-RpcServer -Times 0
		}

		It "Calls Repair-RpcServer when RPC services are unhealthy" {
			Mock Test-RpcServerHealth { $false }
			Mock Repair-RpcServer { $true }

			$null = Get-RpcRetryPolicy -OperationLabel "desktop cleanup"

			Assert-MockCalled Test-RpcServerHealth -Times 1 -Exactly
			Assert-MockCalled Repair-RpcServer -Times 1 -Exactly
		}
	}
}
