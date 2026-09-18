#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Window\Functions\Invoke-VirtualDesktopOperation.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Get-CurrentVirtualDesktopIndex.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Switch-VirtualDesktop.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\New-WaitClock.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\Wait-Until.ps1")
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeVirtualDesktop.ps1")
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeWaitClock.ps1")
	function Clear-WindowCache { }
}

Describe "Switch-VirtualDesktop" {
	BeforeEach {
		Mock Write-LogDebug { }
		# Invoke-VirtualDesktopOperation's RPC retry backoff still sleeps for real; the wait
		# for the switch to land goes through the fake clock below.
		Mock Start-Sleep { }
		Mock Clear-WindowCache { }
		$script:clock = New-FakeWaitClock
		Mock New-WaitClock { $script:clock }
		$null = New-FakeVirtualDesktopSession -DesktopCount 4 -CurrentIndex 0
	}

	It "switches, confirms the desktop is showing, and clears the window cache" {
		Switch-VirtualDesktop -Index 2 | Should -BeTrue

		$global:FakeVirtualDesktop.CurrentIndex | Should -Be 2
		@($global:FakeVirtualDesktop.SwitchLog) | Should -Be @(2)
		Should -Invoke Clear-WindowCache -Times 1 -Exactly
	}

	It "reports a desktop that is already showing as switched without asking the manager to switch" {
		$global:FakeVirtualDesktop.CurrentIndex = 3

		Switch-VirtualDesktop -Index 3 | Should -BeTrue
		$global:FakeVirtualDesktop.SwitchLog.Count | Should -Be 0
		Should -Invoke Clear-WindowCache -Times 0
	}

	It "retries when the switch silently does not land, then resets the session and lands it" {
		# A stale proxy: Switch-Desktop returns without error and nothing changes. Three attempts
		# fail, the session reset makes the fourth stick.
		Mock Switch-Desktop {
			param($Desktop)
			if ($global:FakeVirtualDesktop.ResetCount -gt 0) { $global:FakeVirtualDesktop.CurrentIndex = [int]$Desktop }
		}

		Switch-VirtualDesktop -Index 1 -TimeoutMs 0 -MaxAttempts 3 | Should -BeTrue
		$global:FakeVirtualDesktop.ResetCount | Should -Be 1
		Should -Invoke Switch-Desktop -Times 4 -Exactly
	}

	It "returns false when the desktop never comes on screen, even after the reset" {
		Mock Switch-Desktop { param($Desktop) }

		Switch-VirtualDesktop -Index 1 -MaxAttempts 2 -Clock $script:clock | Should -BeFalse
		Should -Invoke Clear-WindowCache -Times 0
		# Two attempts and the post-reset try each wait the full 750 ms at 10 ms polls: 75
		# sleeps apiece, 2250 ms of virtual time and not a millisecond of real waiting.
		$script:clock.Sleeps.Count | Should -Be 225
		$script:clock.ElapsedMs() | Should -Be 2250
		Should -Invoke New-WaitClock -Times 0
	}

	It "polls at the interval until the switch lands and stops there" {
		# The manager switches asynchronously: the current desktop changes 120 ms of virtual
		# time after Switch-Desktop returns, which a 50 ms poll sees on its fourth check.
		$script:pendingIndex = $null
		Mock Switch-Desktop { param($Desktop) $script:pendingIndex = [int]$Desktop }
		$script:clock = New-FakeWaitClock -OnSleep {
			param($elapsedMs)
			if ($elapsedMs -ge 120 -and $null -ne $script:pendingIndex) { $global:FakeVirtualDesktop.CurrentIndex = $script:pendingIndex }
		}
		Mock New-WaitClock { $script:clock }

		Switch-VirtualDesktop -Index 2 -PollIntervalMs 50 | Should -BeTrue

		$global:FakeVirtualDesktop.CurrentIndex | Should -Be 2
		@($script:clock.Sleeps) | Should -Be @(50, 50, 50)
		Should -Invoke Switch-Desktop -Times 1 -Exactly
		Should -Invoke Clear-WindowCache -Times 1 -Exactly
	}

	It "recovers an RPC failure inside the switch itself through the operation seam" {
		Set-FakeVirtualDesktopFailure -Cmdlet Switch-Desktop -Times 1

		Switch-VirtualDesktop -Index 2 | Should -BeTrue
		$global:FakeVirtualDesktop.CurrentIndex | Should -Be 2
	}

	It "throws when the VirtualDesktop module is not available at all" {
		$null = New-FakeVirtualDesktopSession -DesktopCount 2 -ModuleUnavailable

		{ Switch-VirtualDesktop -Index 1 } | Should -Throw '*VirtualDesktop module is not available*'
	}
}
