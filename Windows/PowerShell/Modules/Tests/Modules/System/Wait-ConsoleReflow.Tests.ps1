#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. "$ModuleRoot\System\Functions\Wait-ConsoleReflow.ps1"
	. "$ModuleRoot\System\Functions\Get-ConsoleWindowSize.ps1"

	if (-not (Get-Command Write-LogDebug -ErrorAction SilentlyContinue)) { function Write-LogDebug { param($Message) } }

	function New-WindowSize {
		param([int]$Width, [int]$Height)
		[pscustomobject]@{ Width = $Width; Height = $Height }
	}
}

Describe "Wait-ConsoleReflow" {
	BeforeEach {
		Mock Write-LogDebug { }

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

		$timer = [Diagnostics.Stopwatch]::StartNew()
		$result = Wait-ConsoleReflow -Before $before -TimeoutMilliseconds 2000 -PollIntervalMilliseconds 1
		$timer.Stop()

		$result.Width | Should -Be 96
		$result.Height | Should -Be 36
		$timer.ElapsedMilliseconds | Should -BeLessThan 1000
		Should -Invoke Get-ConsoleWindowSize -Times 3 -Exactly
	}

	It "returns immediately when the first read already differs" {
		$before = New-WindowSize -Width 80 -Height 30
		$script:Reads = @((New-WindowSize -Width 100 -Height 30))

		$result = Wait-ConsoleReflow -Before $before -TimeoutMilliseconds 2000

		$result.Width | Should -Be 100
		Should -Invoke Get-ConsoleWindowSize -Times 1 -Exactly
	}

	It "returns the unchanged size once the timeout passes" {
		$before = New-WindowSize -Width 80 -Height 30

		$timer = [Diagnostics.Stopwatch]::StartNew()
		$result = Wait-ConsoleReflow -Before $before -TimeoutMilliseconds 60 -PollIntervalMilliseconds 5
		$timer.Stop()

		$result.Width | Should -Be 80
		$result.Height | Should -Be 30
		$timer.ElapsedMilliseconds | Should -BeGreaterOrEqual 60
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

	It "rejects a timeout below one millisecond" {
		{ Wait-ConsoleReflow -Before (New-WindowSize -Width 80 -Height 30) -TimeoutMilliseconds 0 } | Should -Throw
	}
}
