#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Helper\Functions\New-WaitClock.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\Wait-Until.ps1")
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeWaitClock.ps1")
}

Describe "Wait-Until" {
	BeforeEach {
		$script:clock = New-FakeWaitClock
		Mock New-WaitClock { $script:clock }
	}

	It "returns true at once when the condition already holds, without sleeping" {
		$script:checks = 0
		Wait-Until -Condition { $script:checks++; $true } -TimeoutMs 500 | Should -BeTrue

		$script:checks | Should -Be 1
		$script:clock.Sleeps.Count | Should -Be 0
	}

	It "polls at the interval until the condition holds and reports the polls it took" {
		# The world changes at 120 ms; with a 50 ms poll that is seen on the third check.
		Wait-Until -Condition { $script:clock.ElapsedMs() -ge 120 } -TimeoutMs 1000 -PollIntervalMs 50 | Should -BeTrue

		@($script:clock.Sleeps) | Should -Be @(50, 50, 50)
	}

	It "gives up after the budget and returns false, with the check after the last sleep still run" {
		$script:checks = 0
		Wait-Until -Condition { $script:checks++; $false } -TimeoutMs 100 -PollIntervalMs 40 | Should -BeFalse

		# checks at 0, 40 and 80 fail with budget left; the sleep to 120 spends it; the check at
		# 120 still runs before giving up.
		$script:checks | Should -Be 4
		$script:clock.ElapsedMs() | Should -Be 120
	}

	It "sees a change that lands during the final sleep" {
		Wait-Until -Condition { $script:clock.ElapsedMs() -ge 110 } -TimeoutMs 100 -PollIntervalMs 40 | Should -BeTrue
	}

	It "does a single check and never sleeps with a zero budget" {
		$script:checks = 0
		Wait-Until -Condition { $script:checks++; $false } -TimeoutMs 0 | Should -BeFalse

		$script:checks | Should -Be 1
		$script:clock.Sleeps.Count | Should -Be 0
	}

	It "sleeps one interval before the first check with -SleepFirst" {
		$script:checks = 0
		Wait-Until -Condition { $script:checks++; $true } -TimeoutMs 500 -PollIntervalMs 30 -SleepFirst | Should -BeTrue

		@($script:clock.Sleeps) | Should -Be @(30)
		$script:checks | Should -Be 1
	}

	It "measures the budget from the call, not from the clock's creation" {
		$script:clock.Advance(5000)
		$script:checks = 0
		Wait-Until -Condition { $script:checks++; $false } -TimeoutMs 100 -PollIntervalMs 50 | Should -BeFalse

		# checks at 5000 and 5050 with budget left, the check at 5100 spends it: three, not one.
		$script:checks | Should -Be 3
	}

	It "lets the condition record the last state seen through a hashtable it mutates in place" {
		# A plain assignment inside the scriptblock would land in its own scope and be lost; the
		# contract is a reference the caller created.
		$seen = @{ Last = $null }
		$result = Wait-Until -TimeoutMs 60 -PollIntervalMs 30 -Condition {
			$seen.Last = $script:clock.ElapsedMs()
			$false
		}

		$result | Should -BeFalse
		$seen.Last | Should -Be 60
	}

	It "uses the clock it is handed instead of creating one" {
		$other = New-FakeWaitClock
		Wait-Until -Condition { $false } -TimeoutMs 20 -PollIntervalMs 10 -Clock $other | Should -BeFalse

		$other.Sleeps.Count | Should -Be 2
		Should -Invoke New-WaitClock -Times 0
	}

	It "the real clock advances and sleeps for real" {
		$real = New-WaitClock
		$before = $real.ElapsedMs()
		$real.Sleep(20)

		($real.ElapsedMs() - $before) | Should -BeGreaterOrEqual 15
		$real.Now() | Should -BeOfType [datetime]
	}
}
