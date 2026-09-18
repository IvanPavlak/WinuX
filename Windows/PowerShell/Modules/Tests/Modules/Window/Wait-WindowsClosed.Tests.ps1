#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. (Join-Path $ModuleRoot "Helper\Functions\New-WaitClock.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\Wait-Until.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Wait-WindowsClosed.ps1")
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeWaitClock.ps1")

	function Get-WindowHandle { param($ProcessName, $WindowTitle) @() }
	function Clear-WindowCache { }

	function New-TestWindow {
		param($Handle, $Title)
		[PSCustomObject]@{ Handle = [IntPtr]$Handle; Title = $Title }
	}
}

Describe "Wait-WindowsClosed" {
	BeforeEach {
		Mock Clear-WindowCache { }
		Mock Get-WindowHandle { @() }
		# Time is virtual: Sleep advances the clock instead of blocking.
		$script:clock = New-FakeWaitClock
		Mock New-WaitClock { $script:clock }
	}

	It "returns immediately when handed nothing to wait on" {
		Wait-WindowsClosed -Window @() | Should -BeNullOrEmpty

		Should -Invoke Get-WindowHandle -Times 0
		$script:clock.Sleeps.Count | Should -Be 0
	}

	It "reports nothing left when every window has gone" {
		$posted = @((New-TestWindow -Handle 101 -Title 'GitHub'), (New-TestWindow -Handle 203 -Title 'Repo'))

		Wait-WindowsClosed -Window $posted | Should -BeNullOrEmpty
	}

	It "sleeps one poll interval before the first check, because WM_CLOSE was only just posted" {
		Wait-WindowsClosed -Window @((New-TestWindow -Handle 101 -Title 'GitHub')) | Should -BeNullOrEmpty

		@($script:clock.Sleeps) | Should -Be @(250)
		Should -Invoke Get-WindowHandle -Times 1 -Exactly
	}

	It "reports the windows still open once it gives up" {
		Mock Get-WindowHandle { @((New-TestWindow -Handle 203 -Title 'Repo')) }
		$posted = @((New-TestWindow -Handle 101 -Title 'GitHub'), (New-TestWindow -Handle 203 -Title 'Repo'))

		$refused = @(Wait-WindowsClosed -Window $posted -TimeoutMilliseconds 0)

		$refused.Count | Should -Be 1
		$refused[0].Title | Should -Be 'Repo'
	}

	It "gives up after 1500 ms with 250 ms polls: six sleeps, six polls" {
		Mock Get-WindowHandle { @((New-TestWindow -Handle 101 -Title 'GitHub')) }

		$refused = @(Wait-WindowsClosed -Window @((New-TestWindow -Handle 101 -Title 'GitHub')))

		$refused.Count | Should -Be 1
		@($script:clock.Sleeps) | Should -Be @(250, 250, 250, 250, 250, 250)
		$script:clock.ElapsedMs() | Should -Be 1500
		Should -Invoke Get-WindowHandle -Times 6 -Exactly
	}

	It "stops as soon as the windows go, without waiting out the timeout" {
		$script:pollCount = 0
		Mock Get-WindowHandle {
			$script:pollCount++
			if ($script:pollCount -eq 1) { @((New-TestWindow -Handle 101 -Title 'GitHub')) } else { @() }
		}

		Wait-WindowsClosed -Window @((New-TestWindow -Handle 101 -Title 'GitHub')) | Should -BeNullOrEmpty

		$script:pollCount | Should -Be 2
		$script:clock.ElapsedMs() | Should -Be 500
	}

	It "invalidates the window cache before every poll" {
		# Without this the same pre-close snapshot is read each time and every window looks
		# like it refused to close.
		$script:pollCount = 0
		Mock Get-WindowHandle {
			$script:pollCount++
			if ($script:pollCount -lt 3) { @((New-TestWindow -Handle 101 -Title 'GitHub')) } else { @() }
		}

		Wait-WindowsClosed -Window @((New-TestWindow -Handle 101 -Title 'GitHub')) | Out-Null

		Should -Invoke Clear-WindowCache -Times 3
	}

	It "matches by handle, not by a replacement window of the same application" {
		Mock Get-WindowHandle { @((New-TestWindow -Handle 999 -Title 'GitHub')) }

		Wait-WindowsClosed -Window @((New-TestWindow -Handle 101 -Title 'GitHub')) -TimeoutMilliseconds 0 | Should -BeNullOrEmpty
	}

	It "ignores null entries in the input" {
		{ Wait-WindowsClosed -Window @($null, (New-TestWindow -Handle 101 -Title 'GitHub')) } | Should -Not -Throw
	}

	It "polls through the clock it is handed instead of creating one" {
		Mock Get-WindowHandle { @((New-TestWindow -Handle 101 -Title 'GitHub')) }
		$other = New-FakeWaitClock

		$refused = @(Wait-WindowsClosed -Window @((New-TestWindow -Handle 101 -Title 'GitHub')) -TimeoutMilliseconds 100 -PollIntervalMilliseconds 50 -Clock $other)

		$refused.Count | Should -Be 1
		@($other.Sleeps) | Should -Be @(50, 50)
		Should -Invoke New-WaitClock -Times 0
	}
}
