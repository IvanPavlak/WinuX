#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. (Join-Path $ModuleRoot "Helper\Functions\Resolve-HostingTerminalTab.ps1")

	function Get-WindowHandle { param($ProcessName, $WindowTitle) @() }

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
}
