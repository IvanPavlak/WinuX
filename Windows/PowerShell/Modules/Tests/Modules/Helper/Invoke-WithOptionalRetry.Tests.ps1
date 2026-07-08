#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Invoke-WithOptionalRetry.ps1"
}

Describe "Invoke-WithOptionalRetry" {
	Context "Direct execution" {
		It "Runs script block directly when retry is not enabled" {
			Mock Get-Command { $null }

			$result = Invoke-WithOptionalRetry -ScriptBlock { "direct" }

			$result | Should -Be "direct"
		}
	}

	Context "Retry-enabled execution" {
		It "Uses Invoke-WithRetry when enabled and available" {
			Mock Get-Command { @{ Name = 'Invoke-WithRetry' } }
			Mock Invoke-WithRetry { "retried" }

			$result = Invoke-WithOptionalRetry -EnableRetry -ScriptBlock { "ignored" } -MaxAttempts 4 -InitialDelayMs 150

			$result | Should -Be "retried"
			Assert-MockCalled Invoke-WithRetry -Times 1 -Exactly -ParameterFilter { $MaxAttempts -eq 4 -and $InitialDelayMs -eq 150 }
		}

		It "Passes OnRetry to Invoke-WithRetry when provided" {
			$retryHook = { param($ErrorRecord, [int]$Attempt) }
			Mock Get-Command { @{ Name = 'Invoke-WithRetry' } }
			Mock Invoke-WithRetry { "retried" }

			$result = Invoke-WithOptionalRetry -EnableRetry -ScriptBlock { "ignored" } -OnRetry $retryHook

			$result | Should -Be "retried"
			Assert-MockCalled Invoke-WithRetry -Times 1 -Exactly -ParameterFilter { $OnRetry -eq $retryHook }
		}

		It "Falls back to direct execution when retry is enabled but helper is unavailable" {
			Mock Get-Command { $null }

			$result = Invoke-WithOptionalRetry -EnableRetry -ScriptBlock { "fallback" }

			$result | Should -Be "fallback"
		}
	}
}
