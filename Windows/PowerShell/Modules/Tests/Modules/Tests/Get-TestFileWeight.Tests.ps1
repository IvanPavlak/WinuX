#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Tests\Get-TestFileWeight.ps1")
	. (Join-Path $ModuleRoot "Tests\Get-MedianTestDuration.ps1")
}

Describe "Get-TestFileWeight" {
	It "uses the measured duration whenever the file has one, even for an Integration file" {
		Get-TestFileWeight -Timing ([pscustomobject]@{ ms = 1234; tests = 5 }) -ExpectedCount 99 -IsIntegration $true -FileBytes 99999 -MedianMsPerTest 50 |
			Should -Be 1234
	}

	It "gives a never-measured Integration file the heavy seed, whatever its size or count" {
		Get-TestFileWeight -Timing $null -ExpectedCount 2 -IsIntegration $true -FileBytes 100 -MedianMsPerTest 50 | Should -Be 60000
		Get-TestFileWeight -Timing $null -IsIntegration $true -IntegrationSeedMs 5000 | Should -Be 5000
	}

	It "seeds a never-measured file from its counted tests times the median per test" {
		Get-TestFileWeight -Timing $null -ExpectedCount 10 -FileBytes 150000 -MedianMsPerTest 40 | Should -Be (150 + 400)
	}

	It "falls back to file size when nothing is known" {
		Get-TestFileWeight -Timing $null -ExpectedCount 10 -FileBytes 1500 -MedianMsPerTest 0 | Should -Be (150 + 100)
		Get-TestFileWeight -Timing $null -ExpectedCount 0 -FileBytes 1500 -MedianMsPerTest 40 | Should -Be (150 + 100)
	}

	It "treats a cached entry without a duration as unmeasured" {
		Get-TestFileWeight -Timing ([pscustomobject]@{ ms = 0; tests = 3 }) -ExpectedCount 3 -MedianMsPerTest 10 | Should -Be 180
	}
}

Describe "Get-MedianTestDuration" {
	It "returns the median milliseconds per test over the entries that have both numbers" {
		$timings = @{
			'a' = [pscustomobject]@{ ms = 100; tests = 10 }    # 10
			'b' = [pscustomobject]@{ ms = 900; tests = 3 }     # 300
			'c' = [pscustomobject]@{ ms = 40; tests = 2 }      # 20
			'd' = [pscustomobject]@{ ms = 500; tests = 0 }     # ignored
		}
		Get-MedianTestDuration -Timings $timings | Should -Be 20
	}

	It "averages the two middle values for an even count, so one heavy file cannot drag it" {
		$timings = @{
			'a' = [pscustomobject]@{ ms = 10; tests = 1 }
			'b' = [pscustomobject]@{ ms = 30; tests = 1 }
			'c' = [pscustomobject]@{ ms = 50; tests = 1 }
			'd' = [pscustomobject]@{ ms = 90000; tests = 1 }
		}
		Get-MedianTestDuration -Timings $timings | Should -Be 40
	}

	It "returns 0 when nothing is known" {
		Get-MedianTestDuration -Timings @{} | Should -Be 0
		Get-MedianTestDuration -Timings $null | Should -Be 0
	}
}
