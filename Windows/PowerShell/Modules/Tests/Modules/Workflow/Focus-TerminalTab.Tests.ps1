#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Focus-TerminalTab.ps1"

	# Stub before mocking: Confirm-WindowForeground lives in the Window module, which this file
	# never loads, and Mock cannot attach to a command that does not exist.
	function Confirm-WindowForeground { param([IntPtr]$WindowHandle, [int]$BaseSettleMs, [int]$MaxAttempts) $true }
}

Describe "Focus-TerminalTab" {
	BeforeEach {
		Mock Get-Process { @() }
		Mock Write-Host { }
		Mock Write-LogDebug { }
		Mock Write-LogSuccess { }
	}

	It "returns when Windows Terminal is not running" {
		{ Focus-TerminalTab } | Should -Not -Throw
		Should -Invoke Write-Host -Times 0
	}

	It "writes debug message when terminal is not running and debug is enabled" {
		Focus-TerminalTab

		Should -Invoke Write-LogDebug -Times 1
	}

	It "activates exactly the window it was handed, without consulting the process list" {
		# AppActivate takes a PROCESS id, and one Windows Terminal process hosts every one of its
		# windows, so the process path brings forward that process's main window - which on
		# Focus-VirtualDesktop's path can be a sibling living on another virtual desktop, dragging
		# the view straight off the desktop it just switched to.
		Mock Confirm-WindowForeground { $true }

		Focus-TerminalTab -WindowHandle ([IntPtr]4242) -Quiet

		Should -Invoke Confirm-WindowForeground -Times 1 -ParameterFilter { $WindowHandle -eq [IntPtr]4242 }
		Should -Invoke Get-Process -Times 0
	}
}
