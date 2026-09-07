#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Wait-BrowserWindowsClosed.ps1"
	# The liveness probe is its own function precisely so this loop can be tested without the
	# compiled user32 wrapper; load it so Mock can attach.
	. "$FunctionsPath\Test-BrowserWindowOpen.ps1"

	function New-TestWindow {
		param([int]$Handle, [string]$Title)
		[PSCustomObject]@{ Handle = [IntPtr]$Handle; Title = $Title }
	}
}

Describe "Wait-BrowserWindowsClosed" {
	BeforeEach {
		Mock Start-Sleep { }
		# Which handles are still alive; each case scripts it.
		$script:openHandles = @()
		Mock Test-BrowserWindowOpen { $script:openHandles -contains [long]$Handle }
	}

	It "returns nothing when given nothing" {
		@(Wait-BrowserWindowsClosed -Windows @()).Count | Should -Be 0
		@(Wait-BrowserWindowsClosed).Count | Should -Be 0
		Should -Invoke Test-BrowserWindowOpen -Times 0
	}

	It "returns immediately when every window is already gone" {
		$windows = @((New-TestWindow -Handle 1 -Title 'Gone'), (New-TestWindow -Handle 2 -Title 'Gone too'))

		$result = @(Wait-BrowserWindowsClosed -Windows $windows -TimeoutMs 1000)

		$result.Count | Should -Be 0
		Should -Invoke Test-BrowserWindowOpen -Times 2 -Exactly
		Should -Invoke Start-Sleep -Times 0
	}

	It "keeps polling until the window disappears" {
		$script:openHandles = @(4)
		$script:polls = 0
		Mock Start-Sleep {
			$script:polls++
			if ($script:polls -ge 2) { $script:openHandles = @() }
		}

		$result = @(Wait-BrowserWindowsClosed -Windows @((New-TestWindow -Handle 4 -Title 'Slow')) -TimeoutMs 5000 -PollIntervalMs 10)

		$result.Count | Should -Be 0
		Should -Invoke Start-Sleep -Times 2 -Exactly -ParameterFilter { $Milliseconds -eq 10 }
	}

	It "only re-probes the windows that were still open on the previous poll" {
		$script:openHandles = @(5)
		$script:polls = 0
		Mock Start-Sleep {
			$script:polls++
			$script:openHandles = @()
		}
		$windows = @((New-TestWindow -Handle 5 -Title 'Slow'), (New-TestWindow -Handle 6 -Title 'Quick'))

		$result = @(Wait-BrowserWindowsClosed -Windows $windows -TimeoutMs 5000)

		$result.Count | Should -Be 0
		# First poll probes both, the second only the survivor.
		Should -Invoke Test-BrowserWindowOpen -Times 3 -Exactly
	}

	It "returns the windows still standing when the timeout expires" {
		$script:openHandles = @(7)
		$windows = @((New-TestWindow -Handle 7 -Title 'Dialog waiting'), (New-TestWindow -Handle 8 -Title 'Closed'))

		$result = @(Wait-BrowserWindowsClosed -Windows $windows -TimeoutMs 0)

		$result.Count | Should -Be 1
		$result[0].Title | Should -Be 'Dialog waiting'
		Should -Invoke Start-Sleep -Times 0
	}
}
