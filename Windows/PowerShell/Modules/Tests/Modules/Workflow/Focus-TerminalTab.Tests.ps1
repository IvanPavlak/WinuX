#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Focus-TerminalTab.ps1"

	# Stub before mocking: Confirm-WindowForeground lives in the Window module, which this file
	# never loads, and Mock cannot attach to a command that does not exist.
	function Confirm-WindowForeground { param([IntPtr]$WindowHandle, [int]$BaseSettleMs, [int]$MaxAttempts) $true }
	function Get-WindowHandle { param($ProcessName) }
	function Get-WindowsTerminalTabTitles { param([IntPtr]$WindowHandle) }
	function Select-WindowsTerminalTab { param([IntPtr]$WindowHandle, [string]$TabTitle, [int]$TabIndex = -1) }
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

	Context "Landing on a tab by title" {
		BeforeEach {
			Mock Confirm-WindowForeground { $true }
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]100; Title = "Other" }
					[PSCustomObject]@{ Handle = [IntPtr]200; Title = "MyProject.Api" }
				)
			}
			Mock Get-WindowsTerminalTabTitles { @("Other") } -ParameterFilter { $WindowHandle -eq [IntPtr]100 }
			Mock Get-WindowsTerminalTabTitles { @("MyProject.Api", "PowerShell") } -ParameterFilter { $WindowHandle -eq [IntPtr]200 }
			Mock Select-WindowsTerminalTab { $true }
		}

		It "activates the window that holds the tab and selects the tab there, without cycling" {
			Focus-TerminalTab -TargetTitle "PowerShell" -Quiet

			Should -Invoke Confirm-WindowForeground -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]200 }
			Should -Invoke Select-WindowsTerminalTab -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]200 -and $TabTitle -eq "PowerShell" }
			Should -Invoke Get-Process -Times 0
			# The Ctrl+Tab cycle reads the window list on every step; one read means it never ran.
			Should -Invoke Get-WindowHandle -Times 1 -Exactly
		}

		It "falls back to cycling when the tab cannot be selected" {
			Mock Select-WindowsTerminalTab { $false }
			Mock Add-Type { }

			# The window already shows the target title, so the cycle stops at its first read and no
			# real Ctrl+Tab is ever sent from the test run.
			Focus-TerminalTab -TargetTitle "MyProject.Api" -WindowHandle ([IntPtr]200) -Quiet

			Should -Invoke Select-WindowsTerminalTab -Times 1 -Exactly
			Should -Invoke Add-Type -Times 1 -Exactly
			Should -Invoke Get-WindowHandle -Times 1 -Exactly
		}
	}
}
