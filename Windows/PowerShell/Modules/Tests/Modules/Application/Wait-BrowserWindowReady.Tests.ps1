#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$AppFunctionsPath = Join-Path $ModuleRoot "Application\Functions"

	. (Join-Path $ModuleRoot "Helper\Functions\New-WaitClock.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\Wait-Until.ps1")
	. "$AppFunctionsPath\Wait-BrowserWindowReady.ps1"
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeWaitClock.ps1")
}

Describe "Wait-BrowserWindowReady" {
	BeforeEach {
		Mock Write-LogDebug { }
		# Time is virtual: Sleep advances the clock instead of blocking, so a 30 s budget is an
		# exact tick count rather than a real wait.
		$script:clock = New-FakeWaitClock
		Mock New-WaitClock { $script:clock }
	}

	It "returns true immediately when a window already exists" {
		Mock Get-WindowHandle {
			@([PSCustomObject]@{ Handle = [IntPtr]11; Title = 'New Tab - Brave' })
		}

		Wait-BrowserWindowReady -ProcessName "brave" | Should -BeTrue

		$script:clock.Sleeps.Count | Should -Be 0
	}

	It "filters candidate windows by title pattern" {
		# A regular Firefox window must not satisfy a wait for Tor Browser.
		Mock Get-WindowHandle {
			@([PSCustomObject]@{ Handle = [IntPtr]11; Title = 'WinuX - Mozilla Firefox' })
		}

		Wait-BrowserWindowReady -ProcessName "firefox" -TitlePattern "Tor Browser" -TimeoutSeconds 1 | Should -BeFalse

		# One second at 250 ms ticks.
		@($script:clock.Sleeps) | Should -Be @(250, 250, 250, 250)
	}

	It "returns false and logs when no window appears before the timeout" {
		Mock Get-WindowHandle { @() }

		Wait-BrowserWindowReady -ProcessName "brave" -TimeoutSeconds 1 | Should -BeFalse

		Should -Invoke Write-LogDebug -Times 1
	}

	It "gives up after the default 30 s at 250 ms ticks: 120 sleeps, 121 polls" {
		Mock Get-WindowHandle { @() }

		Wait-BrowserWindowReady -ProcessName "brave" | Should -BeFalse

		$script:clock.Sleeps.Count | Should -Be 120
		$script:clock.ElapsedMs() | Should -Be 30000
		# The poll after the last tick still runs before giving up.
		Should -Invoke Get-WindowHandle -Times 121 -Exactly
	}

	It "keeps polling until a window appears" {
		$script:pollCount = 0
		Mock Get-WindowHandle {
			$script:pollCount++
			if ($script:pollCount -ge 3) {
				@([PSCustomObject]@{ Handle = [IntPtr]11; Title = 'New Tab - Brave' })
			}
			else {
				@()
			}
		}

		Wait-BrowserWindowReady -ProcessName "brave" -TimeoutSeconds 5 | Should -BeTrue

		$script:pollCount | Should -Be 3
		@($script:clock.Sleeps) | Should -Be @(250, 250)
	}

	It "polls through the clock it is handed instead of creating one" {
		Mock Get-WindowHandle { @() }
		$other = New-FakeWaitClock

		Wait-BrowserWindowReady -ProcessName "brave" -TimeoutSeconds 1 -Clock $other | Should -BeFalse

		$other.Sleeps.Count | Should -Be 4
		Should -Invoke New-WaitClock -Times 0
	}
}
