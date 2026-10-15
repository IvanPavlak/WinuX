#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. (Join-Path $ModuleRoot "Helper\Functions\Resolve-HostingTerminalTab.ps1")
	# The title probe polls through the real Wait-Until; its first check succeeds or the test
	# mocks it, so no test waits for real.
	. (Join-Path $ModuleRoot "Helper\Functions\Wait-Until.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\New-WaitClock.ps1")

	function Get-WindowHandle { param($ProcessName, $WindowTitle) @() }
	function Clear-WindowCache { }

	# A stand-in for the Process.Parent chain the real walk climbs. Property access is all the
	# function uses, so a plain object chain is a faithful stand-in.
	function New-ProcessChain {
		param([string[]]$ProcessName, [int[]]$Id)

		$node = $null
		for ($i = $ProcessName.Count - 1; $i -ge 0; $i--) {
			$node = [PSCustomObject]@{ ProcessName = $ProcessName[$i]; Id = $Id[$i]; Parent = $node }
		}
		$node
	}

	function New-TerminalWindow {
		param($Handle, $ProcessId, $Title)
		[PSCustomObject]@{ Handle = [IntPtr]$Handle; ProcessId = $ProcessId; ProcessName = 'WindowsTerminal'; Title = $Title }
	}
}

Describe "Resolve-HostingTerminalTab" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Get-WindowHandle { @() }

		# pwsh -> WindowsTerminal (pid 44)
		Mock Get-Process { New-ProcessChain -ProcessName @('pwsh', 'WindowsTerminal') -Id @(1, 44) }

		$script:previousProjectTab = $env:WT_PROJECT_TAB
		Remove-Item Env:WT_PROJECT_TAB -ErrorAction SilentlyContinue
	}

	AfterEach {
		if ($null -ne $script:previousProjectTab -and $script:previousProjectTab -ne '') {
			$env:WT_PROJECT_TAB = $script:previousProjectTab
		}
		else {
			Remove-Item Env:WT_PROJECT_TAB -ErrorAction SilentlyContinue
		}
	}

	It "returns nothing when no Windows Terminal hosts this shell" {
		Mock Get-Process { New-ProcessChain -ProcessName @('pwsh', 'explorer') -Id @(1, 2) }

		Resolve-HostingTerminalTab | Should -BeNullOrEmpty
	}

	It "returns nothing when the parent chain cannot be walked" {
		Mock Get-Process { throw 'access denied' }

		Resolve-HostingTerminalTab | Should -BeNullOrEmpty
	}

	It "returns nothing when the hosting process has no window" {
		Mock Get-WindowHandle { @((New-TerminalWindow -Handle 407 -ProcessId 99 -Title 'other window')) }

		Resolve-HostingTerminalTab | Should -BeNullOrEmpty
	}

	It "picks the window of the hosting terminal, not simply the first one" {
		# Two terminals is the normal state after an -Alongside open, and taking the first would
		# make the flow close a tab in somebody else's window.
		Mock Get-WindowHandle {
			@(
				(New-TerminalWindow -Handle 909 -ProcessId 99 -Title 'a different terminal'),
				(New-TerminalWindow -Handle 407 -ProcessId 44 -Title 'Server.Api')
			)
		}

		$resolved = Resolve-HostingTerminalTab

		$resolved.Handle | Should -Be ([IntPtr]407)
		$resolved.ProcessId | Should -Be 44
	}

	It "walks past intermediate processes to reach the terminal" {
		Mock Get-Process { New-ProcessChain -ProcessName @('pwsh', 'wsl', 'pwsh', 'WindowsTerminal') -Id @(1, 2, 3, 44) }
		Mock Get-WindowHandle { @((New-TerminalWindow -Handle 407 -ProcessId 44 -Title 'Server.Api')) }

		(Resolve-HostingTerminalTab).ProcessId | Should -Be 44
	}

	It "names the tab from WT_PROJECT_TAB when the shell was given one" {
		# Tabs opened with --suppressApplicationTitle never reflect the shell's title, so the
		# window title would name whichever tab is active instead of this one.
		$env:WT_PROJECT_TAB = 'Server.Api'
		Mock Get-WindowHandle { @((New-TerminalWindow -Handle 407 -ProcessId 44 -Title 'some other active tab')) }

		(Resolve-HostingTerminalTab).TabTitle | Should -Be 'Server.Api'
	}

	It "falls back to the window title when no project tab is set" {
		Mock Get-WindowHandle { @((New-TerminalWindow -Handle 407 -ProcessId 44 -Title 'pwsh')) }

		(Resolve-HostingTerminalTab).TabTitle | Should -Be 'pwsh'
	}

	It "reports the only window of the hosting terminal as identified" {
		Mock Get-WindowHandle { @((New-TerminalWindow -Handle 407 -ProcessId 44 -Title 'pwsh')) }

		(Resolve-HostingTerminalTab).Exact | Should -BeTrue
	}

	Context "several windows in one terminal process" {
		# Current Windows Terminal versions host every window in one process, so the parent-process
		# walk alone cannot tell the windows apart.
		BeforeEach {
			$script:previousConsoleTitle = $Host.UI.RawUI.WindowTitle
		}

		AfterEach {
			$Host.UI.RawUI.WindowTitle = $script:previousConsoleTitle
		}

		It "picks the one window whose active tab is this shell's project tab" {
			$env:WT_PROJECT_TAB = 'Server.Api'
			Mock Get-WindowHandle {
				@(
					(New-TerminalWindow -Handle 909 -ProcessId 44 -Title 'PowerShell'),
					(New-TerminalWindow -Handle 407 -ProcessId 44 -Title 'Server.Api')
				)
			}

			$resolved = Resolve-HostingTerminalTab

			$resolved.Handle | Should -Be ([IntPtr]407)
			$resolved.Exact | Should -BeTrue
			$resolved.TabTitle | Should -Be 'Server.Api'
		}

		It "finds its own window through a title probe and restores the shell's title" {
			$Host.UI.RawUI.WindowTitle = 'my shell'
			# Window 407 is this shell's: its title follows whatever the shell sets, the way Windows
			# Terminal mirrors the active tab's title. Window 909 is another window.
			Mock Get-WindowHandle {
				@(
					(New-TerminalWindow -Handle 909 -ProcessId 44 -Title 'PowerShell'),
					(New-TerminalWindow -Handle 407 -ProcessId 44 -Title $Host.UI.RawUI.WindowTitle)
				)
			}

			$resolved = Resolve-HostingTerminalTab

			$resolved.Handle | Should -Be ([IntPtr]407)
			$resolved.Exact | Should -BeTrue
			$resolved.TabTitle | Should -Be 'my shell'
			$Host.UI.RawUI.WindowTitle | Should -Be 'my shell'
		}

		It "falls back to the probe when the project tab title is shown by more than one window" {
			$env:WT_PROJECT_TAB = 'Server.Api'
			Mock Get-WindowHandle {
				@(
					(New-TerminalWindow -Handle 909 -ProcessId 44 -Title 'Server.Api'),
					(New-TerminalWindow -Handle 407 -ProcessId 44 -Title 'Server.Api')
				)
			}
			Mock Wait-Until { $false }

			$resolved = Resolve-HostingTerminalTab

			Should -Invoke Wait-Until -Times 1 -Exactly
			$resolved.Exact | Should -BeFalse
		}

		It "returns the first window as a guess when nothing identifies it" {
			Mock Get-WindowHandle {
				@(
					(New-TerminalWindow -Handle 909 -ProcessId 44 -Title 'PowerShell'),
					(New-TerminalWindow -Handle 407 -ProcessId 44 -Title 'PowerShell')
				)
			}
			# The probe never shows up (a tab that cannot retitle itself).
			Mock Wait-Until { $false }

			$resolved = Resolve-HostingTerminalTab

			$resolved.Handle | Should -Be ([IntPtr]909)
			$resolved.Exact | Should -BeFalse
		}

		It "does not probe when the project tab title identifies the window" {
			$env:WT_PROJECT_TAB = 'Server.Api'
			Mock Get-WindowHandle {
				@(
					(New-TerminalWindow -Handle 909 -ProcessId 44 -Title 'PowerShell'),
					(New-TerminalWindow -Handle 407 -ProcessId 44 -Title 'Server.Api')
				)
			}
			Mock Wait-Until { $true }

			$null = Resolve-HostingTerminalTab

			Should -Invoke Wait-Until -Times 0
		}
	}
}
