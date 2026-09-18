#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. (Join-Path $ModuleRoot "Helper\Functions\New-WaitClock.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\Wait-Until.ps1")
	. "$FunctionsPath\Wait-BrowserWindowsClosed.ps1"
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeWaitClock.ps1")
	# The liveness probe is the Window module's Test-WindowVisible; stubbed so Mock can attach
	# without the compiled user32 wrapper and no real handle is ever probed.
	function Test-WindowVisible { param([IntPtr]$Handle) $false }

	function New-TestWindow {
		param([int]$Handle, [string]$Title)
		[PSCustomObject]@{ Handle = [IntPtr]$Handle; Title = $Title }
	}
}

Describe "Wait-BrowserWindowsClosed" {
	BeforeEach {
		# Time is virtual: Sleep advances the clock instead of blocking. A case that needs the
		# world to change mid-wait builds its own clock with -OnSleep.
		$script:clock = New-FakeWaitClock
		Mock New-WaitClock { $script:clock }
		# Which handles are still alive; each case scripts it.
		$script:openHandles = @()
		Mock Test-WindowVisible { $script:openHandles -contains [long]$Handle }
	}

	It "returns nothing when given nothing" {
		@(Wait-BrowserWindowsClosed -Windows @()).Count | Should -Be 0
		@(Wait-BrowserWindowsClosed).Count | Should -Be 0
		Should -Invoke Test-WindowVisible -Times 0
	}

	It "returns immediately when every window is already gone" {
		$windows = @((New-TestWindow -Handle 1 -Title 'Gone'), (New-TestWindow -Handle 2 -Title 'Gone too'))

		$result = @(Wait-BrowserWindowsClosed -Windows $windows -TimeoutMs 1000)

		$result.Count | Should -Be 0
		Should -Invoke Test-WindowVisible -Times 2 -Exactly
		$script:clock.Sleeps.Count | Should -Be 0
	}

	It "keeps polling until the window disappears" {
		$script:openHandles = @(4)
		# The window goes at 20 ms of virtual time: seen on the third check, after two sleeps.
		$script:clock = New-FakeWaitClock -OnSleep { param($elapsedMs) if ($elapsedMs -ge 20) { $script:openHandles = @() } }
		Mock New-WaitClock { $script:clock }

		$result = @(Wait-BrowserWindowsClosed -Windows @((New-TestWindow -Handle 4 -Title 'Slow')) -TimeoutMs 5000 -PollIntervalMs 10)

		$result.Count | Should -Be 0
		@($script:clock.Sleeps) | Should -Be @(10, 10)
		Should -Invoke Test-WindowVisible -Times 3 -Exactly
	}

	It "only re-probes the windows that were still open on the previous poll" {
		$script:openHandles = @(5)
		$script:clock = New-FakeWaitClock -OnSleep { param($elapsedMs) $script:openHandles = @() }
		Mock New-WaitClock { $script:clock }
		$windows = @((New-TestWindow -Handle 5 -Title 'Slow'), (New-TestWindow -Handle 6 -Title 'Quick'))

		$result = @(Wait-BrowserWindowsClosed -Windows $windows -TimeoutMs 5000)

		$result.Count | Should -Be 0
		# First poll probes both, the second only the survivor.
		Should -Invoke Test-WindowVisible -Times 3 -Exactly
		$script:clock.Sleeps.Count | Should -Be 1
	}

	It "returns the windows still standing when the timeout expires" {
		$script:openHandles = @(7)
		$windows = @((New-TestWindow -Handle 7 -Title 'Dialog waiting'), (New-TestWindow -Handle 8 -Title 'Closed'))

		$result = @(Wait-BrowserWindowsClosed -Windows $windows -TimeoutMs 0)

		$result.Count | Should -Be 1
		$result[0].Title | Should -Be 'Dialog waiting'
		$script:clock.Sleeps.Count | Should -Be 0
	}

	It "gives up after the default 4000 ms at 100 ms polls: 40 sleeps, 41 probes" {
		$script:openHandles = @(7)

		$result = @(Wait-BrowserWindowsClosed -Windows @((New-TestWindow -Handle 7 -Title 'Dialog waiting')))

		$result.Count | Should -Be 1
		$script:clock.Sleeps.Count | Should -Be 40
		$script:clock.ElapsedMs() | Should -Be 4000
		# The check after the last sleep still runs before giving up.
		Should -Invoke Test-WindowVisible -Times 41 -Exactly
	}

	It "polls through the clock it is handed instead of creating one" {
		$script:openHandles = @(7)
		$other = New-FakeWaitClock

		$result = @(Wait-BrowserWindowsClosed -Windows @((New-TestWindow -Handle 7 -Title 'Dialog waiting')) -TimeoutMs 300 -PollIntervalMs 100 -Clock $other)

		$result.Count | Should -Be 1
		@($other.Sleeps) | Should -Be @(100, 100, 100)
		Should -Invoke New-WaitClock -Times 0
	}
}
