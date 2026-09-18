#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. "$ModuleRoot\Helper\Functions\New-WaitClock.ps1"
	. "$ModuleRoot\Helper\Functions\Wait-Until.ps1"
	. "$ModuleRoot\System\Functions\Wait-ConsoleReflow.ps1"
	. "$ModuleRoot\System\Functions\Get-ConsoleWindowSize.ps1"
	. "$ModuleRoot\Tests\Modules\Support\FakeWaitClock.ps1"

	if (-not (Get-Command Write-LogDebug -ErrorAction SilentlyContinue)) { function Write-LogDebug { param($Message) } }

	function New-WindowSize {
		param([int]$Width, [int]$Height)
		[pscustomobject]@{ Width = $Width; Height = $Height }
	}
}

Describe "Wait-ConsoleReflow" {
	BeforeEach {
		Mock Write-LogDebug { }

		# Time is virtual: Sleep advances the clock instead of blocking, so a timeout case
		# asserts its exact poll count instead of measuring wall-clock time.
		$script:clock = New-FakeWaitClock
		Mock New-WaitClock { $script:clock }

		# A scripted console: each read consumes the next queued size; a drained queue keeps
		# returning the last one.
		$script:Reads = @()
		$script:LastRead = New-WindowSize -Width 80 -Height 30
		Mock Get-ConsoleWindowSize {
			if ($script:Reads.Count -gt 0) {
				$next = $script:Reads[0]
				$script:Reads = @($script:Reads | Select-Object -Skip 1)
				return $next
			}
			return $script:LastRead
		}
	}

	It "returns the new size as soon as the window changes" {
		$before = New-WindowSize -Width 80 -Height 30
		$script:Reads = @(
			(New-WindowSize -Width 80 -Height 30)
			(New-WindowSize -Width 80 -Height 30)
			(New-WindowSize -Width 96 -Height 36)
		)
		$script:LastRead = New-WindowSize -Width 96 -Height 36

		$result = Wait-ConsoleReflow -Before $before -TimeoutMilliseconds 2000 -PollIntervalMilliseconds 1

		$result.Width | Should -Be 96
		$result.Height | Should -Be 36
		# Two unchanged reads, two sleeps, then the changed read ends the wait well inside the budget.
		@($script:clock.Sleeps) | Should -Be @(1, 1)
		Should -Invoke Get-ConsoleWindowSize -Times 3 -Exactly
	}

	It "returns immediately when the first read already differs" {
		$before = New-WindowSize -Width 80 -Height 30
		$script:Reads = @((New-WindowSize -Width 100 -Height 30))

		$result = Wait-ConsoleReflow -Before $before -TimeoutMilliseconds 2000

		$result.Width | Should -Be 100
		Should -Invoke Get-ConsoleWindowSize -Times 1 -Exactly
		$script:clock.Sleeps.Count | Should -Be 0
	}

	It "returns the unchanged size once the timeout passes: 60 ms at 5 ms polls is 12 sleeps" {
		$before = New-WindowSize -Width 80 -Height 30

		$result = Wait-ConsoleReflow -Before $before -TimeoutMilliseconds 60 -PollIntervalMilliseconds 5

		$result.Width | Should -Be 80
		$result.Height | Should -Be 30
		$script:clock.Sleeps.Count | Should -Be 12
		$script:clock.ElapsedMs() | Should -Be 60
		# The read after the last sleep still runs before giving up.
		Should -Invoke Get-ConsoleWindowSize -Times 13 -Exactly
	}

	It "treats a change in height alone as a reflow" {
		$before = New-WindowSize -Width 80 -Height 30
		$script:Reads = @((New-WindowSize -Width 80 -Height 34))
		$script:LastRead = New-WindowSize -Width 80 -Height 34

		$result = Wait-ConsoleReflow -Before $before -TimeoutMilliseconds 2000 -PollIntervalMilliseconds 1

		$result.Height | Should -Be 34
	}

	It "treats a change in width alone as a reflow" {
		$before = New-WindowSize -Width 80 -Height 30
		$script:Reads = @((New-WindowSize -Width 85 -Height 30))
		$script:LastRead = New-WindowSize -Width 85 -Height 30

		$result = Wait-ConsoleReflow -Before $before -TimeoutMilliseconds 2000 -PollIntervalMilliseconds 1

		$result.Width | Should -Be 85
	}

	It "logs the reflow when the size changed and the timeout when it did not" {
		$before = New-WindowSize -Width 80 -Height 30
		$script:Reads = @((New-WindowSize -Width 90 -Height 30))
		$script:LastRead = New-WindowSize -Width 90 -Height 30
		Wait-ConsoleReflow -Before $before -TimeoutMilliseconds 2000 | Out-Null
		Should -Invoke Write-LogDebug -Times 1 -Exactly -ParameterFilter { $Message -like "*80x30 => 90x30*" }

		$script:LastRead = New-WindowSize -Width 80 -Height 30
		Wait-ConsoleReflow -Before $before -TimeoutMilliseconds 20 -PollIntervalMilliseconds 5 | Out-Null
		Should -Invoke Write-LogDebug -Times 1 -Exactly -ParameterFilter { $Message -like "*no reflow*" }
	}

	It "reports the virtual time the reflow took in its log line" {
		$before = New-WindowSize -Width 80 -Height 30
		$script:Reads = @((New-WindowSize -Width 80 -Height 30), (New-WindowSize -Width 90 -Height 30))
		$script:LastRead = New-WindowSize -Width 90 -Height 30

		Wait-ConsoleReflow -Before $before -TimeoutMilliseconds 2000 -PollIntervalMilliseconds 10 | Out-Null

		Should -Invoke Write-LogDebug -Times 1 -Exactly -ParameterFilter { $Message -like "*after 10ms" }
	}

	It "polls through the clock it is handed instead of creating one" {
		$other = New-FakeWaitClock

		$result = Wait-ConsoleReflow -Before (New-WindowSize -Width 80 -Height 30) -TimeoutMilliseconds 30 -PollIntervalMilliseconds 10 -Clock $other

		$result.Width | Should -Be 80
		@($other.Sleeps) | Should -Be @(10, 10, 10)
		Should -Invoke New-WaitClock -Times 0
	}

	It "rejects a timeout below one millisecond" {
		{ Wait-ConsoleReflow -Before (New-WindowSize -Width 80 -Height 30) -TimeoutMilliseconds 0 } | Should -Throw
	}
}
