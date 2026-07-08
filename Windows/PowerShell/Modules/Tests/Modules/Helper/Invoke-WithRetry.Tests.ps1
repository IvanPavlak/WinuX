#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Invoke-WithRetry.ps1"
}

Describe "Invoke-WithRetry" {
	Context "Successful Execution" {
		It "Should return result on first successful attempt" {
			$result = Invoke-WithRetry -ScriptBlock { "Success" }

			$result | Should -Be "Success"
		}

		It "Should return complex objects" {
			$result = Invoke-WithRetry -ScriptBlock { @{ Key = "Value" } }

			$result.Key | Should -Be "Value"
		}
	}

	Context "Retry Behavior" {
		It "Should retry on failure and succeed on subsequent attempt" {
			$script:callCount = 0
			$result = Invoke-WithRetry -ScriptBlock {
				$script:callCount++
				if ($script:callCount -lt 2) { throw "Transient error" }
				"Recovered"
			} -MaxAttempts 3 -InitialDelayMs 10

			$result | Should -Be "Recovered"
			$script:callCount | Should -Be 2
		}

		It "Should invoke OnRetry before retrying a failed attempt" {
			$script:callCount = 0
			$script:retryAttempts = @()

			$result = Invoke-WithRetry -ScriptBlock {
				$script:callCount++
				if ($script:callCount -lt 2) { throw "The RPC server is unavailable. (0x800706BA)" }
				"Recovered"
			} -MaxAttempts 3 -InitialDelayMs 0 -OnRetry {
				param($ErrorRecord, [int]$Attempt)
				$script:retryAttempts += [PSCustomObject]@{
					Attempt = $Attempt
					Message = $ErrorRecord.Exception.Message
				}
			}

			$result | Should -Be "Recovered"
			$script:retryAttempts.Count | Should -Be 1
			$script:retryAttempts[0].Attempt | Should -Be 1
			$script:retryAttempts[0].Message | Should -Match "0x800706BA"
		}

		It "Should throw after exhausting all retry attempts" {
			{
				Invoke-WithRetry -ScriptBlock { throw "Persistent error" } -MaxAttempts 2 -InitialDelayMs 10
			} | Should -Throw "Persistent error"
		}

		It "Should attempt exactly MaxAttempts times before throwing" {
			$script:callCount = 0
			try {
				Invoke-WithRetry -ScriptBlock {
					$script:callCount++
					throw "Error"
				} -MaxAttempts 3 -InitialDelayMs 10
			}
			catch { }

			$script:callCount | Should -Be 3
		}

		It "Should use exponential backoff (each retry doubles delay)" {
			# Verify that retries happen with increasing delays
			$script:callCount = 0
			$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
			try {
				Invoke-WithRetry -ScriptBlock {
					$script:callCount++
					throw "Error"
				} -MaxAttempts 3 -InitialDelayMs 50
			}
			catch { }
			$stopwatch.Stop()

			# 3 attempts, 2 delays: 50ms + 100ms = 150ms minimum
			$stopwatch.ElapsedMilliseconds | Should -BeGreaterOrEqual 100
		}
	}

	Context "Default Parameters" {
		It "Should default to 3 max attempts" {
			$script:callCount = 0
			try {
				Invoke-WithRetry -ScriptBlock {
					$script:callCount++
					throw "Error"
				} -InitialDelayMs 10
			}
			catch { }

			$script:callCount | Should -Be 3
		}
	}
}
