#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. (Join-Path $ModuleRoot "Window\Functions\Focus-VirtualDesktop.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\ConvertTo-InternalDesktopIndex.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Get-WindowDesktopIndex.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Switch-VirtualDesktop.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Get-CurrentVirtualDesktopIndex.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Invoke-VirtualDesktopOperation.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\New-WaitClock.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\Wait-Until.ps1")
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeVirtualDesktop.ps1")
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeWaitClock.ps1")

	function Get-WindowHandle { param($ProcessName, $WindowTitle) @() }
	function Focus-TerminalTab { param([IntPtr]$WindowHandle, [switch]$Quiet) }
	function Clear-WindowCache { }

	function New-TestWindow {
		param([int]$Handle, [string]$ProcessName, [string]$Title)
		[PSCustomObject]@{ Handle = [IntPtr]$Handle; ProcessName = $ProcessName; Title = $Title }
	}
}

Describe "Focus-VirtualDesktop" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogDebug { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		# Invoke-VirtualDesktopOperation's RPC retry backoff still sleeps for real; the switch
		# waits inside Switch-VirtualDesktop run on the fake clock, so a desktop that never lands
		# costs virtual milliseconds instead of three real seconds.
		Mock Start-Sleep { }
		Mock Clear-WindowCache { }
		$script:clock = New-FakeWaitClock
		Mock New-WaitClock { $script:clock }
		# The native ForceForegroundWindow cannot run in a test; the terminal path never reaches
		# it as long as Focus-TerminalTab does not throw.
		Mock Focus-TerminalTab { }
		Mock Get-WindowHandle { @() }

		# Four desktops, desktop 0 showing.
		$null = New-FakeVirtualDesktopSession -DesktopCount 4 -CurrentIndex 0
	}

	It "warns and returns when the VirtualDesktop module is not available" {
		$null = New-FakeVirtualDesktopSession -DesktopCount 4 -ModuleUnavailable

		Focus-VirtualDesktop -DesktopNumber 2

		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "*VirtualDesktop module unavailable*" }
		$global:FakeVirtualDesktop.SwitchLog.Count | Should -Be 0
		Should -Invoke Get-WindowHandle -Times 0
	}

	It "converts DesktopNumber and DesktopOffset to the 0-based index and switches there" {
		# Desktop 1 of an alongside workspace that starts after two existing desktops is index 2.
		Focus-VirtualDesktop -DesktopNumber 1 -DesktopOffset 2

		@($global:FakeVirtualDesktop.SwitchLog) | Should -Be @(2)
		$global:FakeVirtualDesktop.CurrentIndex | Should -Be 2
	}

	It "defaults to the first desktop" {
		$global:FakeVirtualDesktop.CurrentIndex = 3

		Focus-VirtualDesktop

		$global:FakeVirtualDesktop.CurrentIndex | Should -Be 0
	}

	It "reports failure and does not look for windows when the switch does not land" {
		# A stale proxy: Switch-Desktop returns without error and nothing changes, even after the
		# session reset.
		Mock Switch-Desktop { param($Desktop) }

		Focus-VirtualDesktop -DesktopNumber 2

		Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like "Failed to focus Virtual Desktop 2*" }
		Should -Invoke Write-LogSuccess -Times 0
		Should -Invoke Get-WindowHandle -Times 0
		Should -Invoke Focus-TerminalTab -Times 0
		# Three attempts and the post-reset try each wait out 750 ms at 10 ms polls.
		$script:clock.Sleeps.Count | Should -Be 300
		$script:clock.ElapsedMs() | Should -Be 3000
	}

	It "recovers a stale session inside the switch and still focuses the desktop" {
		Set-FakeVirtualDesktopFailure -Cmdlet Switch-Desktop -Times 1
		Mock Get-WindowHandle { @(New-TestWindow -Handle 700 -ProcessName 'WindowsTerminal' -Title 'pwsh') }
		$global:FakeVirtualDesktop.WindowDesktops[[int64]700] = 1

		Focus-VirtualDesktop -DesktopNumber 2

		$global:FakeVirtualDesktop.CurrentIndex | Should -Be 1
		$global:FakeVirtualDesktop.ResetCount | Should -Be 1
		Should -Invoke Write-LogSuccess -Times 1 -Exactly
	}

	It "focuses a terminal on the target desktop by its verified handle" {
		Mock Get-WindowHandle {
			@(
				(New-TestWindow -Handle 700 -ProcessName 'WindowsTerminal' -Title 'pwsh'),
				(New-TestWindow -Handle 800 -ProcessName 'chrome' -Title 'Browser')
			)
		}
		$global:FakeVirtualDesktop.WindowDesktops[[int64]700] = 1
		$global:FakeVirtualDesktop.WindowDesktops[[int64]800] = 1

		Focus-VirtualDesktop -DesktopNumber 2

		Should -Invoke Focus-TerminalTab -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]700 -and $Quiet }
		Should -Invoke Write-LogSuccess -Times 1 -Exactly -ParameterFilter { $Message -eq "Focused Virtual Desktop 2!" }
		Should -Invoke Write-LogWarning -Times 0
	}

	It "warns when no window lives on the target desktop" {
		Mock Get-WindowHandle { @(New-TestWindow -Handle 700 -ProcessName 'WindowsTerminal' -Title 'pwsh') }
		$global:FakeVirtualDesktop.WindowDesktops[[int64]700] = 0

		Focus-VirtualDesktop -DesktopNumber 2

		$global:FakeVirtualDesktop.CurrentIndex | Should -Be 1
		Should -Invoke Focus-TerminalTab -Times 0
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "Switched to Virtual Desktop 2, but found no window to focus!" }
		Should -Invoke Write-LogSuccess -Times 0
	}

	It "skips windows whose desktop is not the target, including a terminal on another desktop" {
		# One terminal process hosts every one of its windows, so the terminal on desktop 0 must
		# never be the one handed to Focus-TerminalTab - activating it would drag the view back.
		Mock Get-WindowHandle {
			@(
				(New-TestWindow -Handle 600 -ProcessName 'WindowsTerminal' -Title 'other shell'),
				(New-TestWindow -Handle 700 -ProcessName 'WindowsTerminal' -Title 'pwsh')
			)
		}
		$global:FakeVirtualDesktop.WindowDesktops[[int64]600] = 0
		$global:FakeVirtualDesktop.WindowDesktops[[int64]700] = 1

		Focus-VirtualDesktop -DesktopNumber 2

		Should -Invoke Focus-TerminalTab -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]700 }
		Should -Invoke Focus-TerminalTab -Times 0 -ParameterFilter { $WindowHandle -eq [IntPtr]600 }
	}

	It "skips a window that has no resolvable desktop and keeps looking" {
		# Handle 999 is unknown to the desktop manager (a window that closed mid-scan, or a shell
		# surface); the terminal after it is the one that gets the focus.
		Mock Get-WindowHandle {
			@(
				(New-TestWindow -Handle 999 -ProcessName 'WindowsTerminal' -Title 'gone'),
				(New-TestWindow -Handle 700 -ProcessName 'WindowsTerminal' -Title 'pwsh')
			)
		}
		$global:FakeVirtualDesktop.WindowDesktops[[int64]700] = 1

		Focus-VirtualDesktop -DesktopNumber 2

		Should -Invoke Focus-TerminalTab -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]700 }
	}
}
