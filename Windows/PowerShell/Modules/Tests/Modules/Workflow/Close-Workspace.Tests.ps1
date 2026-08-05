#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	# The tracker read/write path is exercised for real against a temp file, so these tests cover
	# Close-Workspace together with the persistence it depends on rather than around it.
	. "$FunctionsPath\Format-WorkspaceStateContent.ps1"
	. "$FunctionsPath\Get-WorkspaceState.ps1"
	. "$FunctionsPath\Save-WorkspaceState.ps1"
	. "$FunctionsPath\Close-Workspace.ps1"

	$script:TestStateDir = Join-Path $env:TEMP ("CloseWorkspaceTests_" + $PID)
	$script:TestStatePath = Join-Path $script:TestStateDir "OpenWorkspaces.txt"

	function Resolve-Selection { param($InputObject, $OptionList, $MenuTitle, $PromptMessage, [switch]$AllowEmptyPromptResponse, [switch]$AllowMultipleSelections) $InputObject }
	function Get-WindowHandle { param($ProcessName, $WindowTitle) @() }
	function Clear-WindowCache { }
	function Get-WindowsTerminalTabTitles { param($WindowHandle) @() }
	function Close-WindowsTerminalTab { param($WindowHandle, $TabTitle) $true }
	function Resolve-HostingTerminalTab { $null }
	function Ensure-DesktopVisible { param($WindowHandle, $DesktopIndex) $null }
	function Wait-WindowsClosed { param($Window, $TimeoutMilliseconds, $PollIntervalMilliseconds) @() }
	function Get-WindowDesktopIndex { param([IntPtr]$WindowHandle) -1 }
	function Remove-VirtualDesktops { param([switch]$EmptyOnly, [int[]]$Index) }
	function Focus-TerminalTab { param($TargetTitle, [switch]$Quiet) }
	function Invoke-TerminateWindowsTerminalTabsExit { }
	function Get-WorkspaceOpenDelta { param($Workspace, $ExistingWindowHandles, $ExistingTerminalTabs, $DesktopOffset, [switch]$Alongside) }

	# Handles here are deliberately not multiples of four, so they can never collide with a real
	# HWND: the WM_CLOSE this function posts is then guaranteed to be a no-op in the test process.
	function New-TestWindow {
		param($Handle, $ProcessId, $ProcessName, $Title)
		[PSCustomObject]@{
			Handle      = [IntPtr]$Handle
			ProcessId   = $ProcessId
			ProcessName = $ProcessName
			Title       = $Title
		}
	}

	function New-WindowRecord {
		param($Handle, $ProcessId, $ProcessName, $Title)
		[ordered]@{ Handle = $Handle; ProcessId = $ProcessId; ProcessName = $ProcessName; Title = $Title }
	}

	function New-TabRecord {
		param($WindowHandle, $Title)
		[ordered]@{ WindowHandle = $WindowHandle; Title = $Title }
	}

	function New-Entry {
		param($Workspace, [switch]$Alongside, $DesktopOffset = 0, $Windows = @(), $TerminalTabs = @())
		[ordered]@{
			Workspace     = $Workspace
			Alongside     = [bool]$Alongside
			DesktopOffset = $DesktopOffset
			OpenedUtc     = '2026-07-27T09:00:00.0000000+00:00'
			ShellPid      = 4242
			Windows       = $Windows
			TerminalTabs  = $TerminalTabs
		}
	}

	function Set-Tracker {
		param([object[]]$Entry)
		Set-Content -LiteralPath $script:TestStatePath -Value (Format-WorkspaceStateContent -Entry $Entry) -NoNewline -Encoding UTF8
	}

	function Get-TrackedWorkspaceName {
		@((Get-WorkspaceState -StatePath $script:TestStatePath).Entries | ForEach-Object { $_.Workspace })
	}
}

Describe "Close-Workspace" {
	BeforeEach {
		$script:postedWindows = @()
		$script:closedTabs = @()

		# Windows Terminal is modelled rather than stubbed flat: a tab leaves the strip when it is
		# closed, and the window itself disappears with its last tab. Close-Workspace relies on
		# both, so a stub that never changed would let a regression pass.
		$script:liveTabTitles = @('pwsh', 'Server.Api', 'Server.Ui')
		$script:liveTerminalWindows = @((New-TestWindow -Handle 407 -ProcessId 44 -ProcessName 'WindowsTerminal' -Title 'Server.Api'))
		$script:tabsUnreadable = $false

		# Windows Terminal only composes its tab strip while its virtual desktop is on screen, so
		# "unreadable until the desktop is made visible" is a first-class state here.
		$script:tabsNeedDesktop = $false
		$script:desktopVisible = $false
		$script:desktopSwitches = @()

		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogDebug { }
		Mock Write-LogList { }

		Mock Resolve-Selection {
			param($InputObject, $OptionList, $MenuTitle, $PromptMessage, [switch]$AllowEmptyPromptResponse, [switch]$AllowMultipleSelections)
			@($InputObject | Where-Object { $entry = $_; $OptionList | Where-Object { $_ -ieq $entry } })
		}
		Mock Clear-WindowCache { }
		Mock Get-WindowsTerminalTabTitles {
			if ($script:tabsUnreadable) { return $null }
			if ($script:tabsNeedDesktop -and -not $script:desktopVisible) { return $null }
			@($script:liveTabTitles)
		}
		Mock Ensure-DesktopVisible {
			param($WindowHandle, $DesktopIndex)
			if ($PSBoundParameters.ContainsKey('DesktopIndex')) {
				$script:desktopSwitches += "restore:$DesktopIndex"
				$script:desktopVisible = $false
				return $null
			}
			$script:desktopSwitches += "window:$([int64]$WindowHandle)"
			$script:desktopVisible = $true
			return 1
		}
		Mock Close-WindowsTerminalTab {
			param($WindowHandle, $TabTitle)
			$script:closedTabs += $TabTitle
			$script:liveTabTitles = @($script:liveTabTitles | Where-Object { $_ -ne $TabTitle })
			if ($script:liveTabTitles.Count -eq 0) { $script:liveTerminalWindows = @() }
			$true
		}
		Mock Resolve-HostingTerminalTab { $null }
		# -1 everywhere by default: no window has a known desktop, so the desktop-membership claim and
		# the desktop removal both no-op and every test that is not about them is unaffected. String
		# keys on purpose - a hashtable with Int32 keys never matches an Int64 lookup in .NET.
		$script:desktopOfHandle = @{}
		$script:removedDesktopIndexes = @()
		Mock Get-WindowDesktopIndex {
			param([IntPtr]$WindowHandle)
			$known = $script:desktopOfHandle["$([int64]$WindowHandle)"]
			if ($null -eq $known) { -1 } else { $known }
		}
		Mock Remove-VirtualDesktops {
			param([switch]$EmptyOnly, [int[]]$Index)
			# ContainsKey, not truthiness: -Index @(0) unwraps to a falsy 0, and desktop 0 is exactly
			# where a plain workspace lands.
			if ($PSBoundParameters.ContainsKey('Index')) { $script:removedDesktopIndexes += @($Index) }
		}
		Mock Focus-TerminalTab { }
		Mock Invoke-TerminateWindowsTerminalTabsExit { }

		# Everything Close-Workspace decides to close is handed to Wait-WindowsClosed, so this is
		# the observation point for the WM_CLOSE pass.
		Mock Wait-WindowsClosed {
			param($Window, $TimeoutMilliseconds, $PollIntervalMilliseconds)
			$script:postedWindows = @($Window)
			@()
		}

		Mock Get-WindowHandle {
			param($ProcessName, $WindowTitle)
			# The terminal-only query is answered from the live set, so it reflects a window that
			# the tab pass already took down.
			if ($ProcessName -eq 'WindowsTerminal') { return @($script:liveTerminalWindows) }
			@(
				(New-TestWindow -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub'),
				(New-TestWindow -Handle 203 -ProcessId 22 -ProcessName 'Code' -Title 'Repo - VS Code'),
				(New-TestWindow -Handle 305 -ProcessId 33 -ProcessName 'Obsidian' -Title 'Vault - Obsidian')
			) + @($script:liveTerminalWindows)
		}

		if (Test-Path $script:TestStateDir) { Remove-Item $script:TestStateDir -Recurse -Force }
		New-Item -ItemType Directory -Path $script:TestStateDir -Force | Out-Null
	}

	AfterEach {
		if (Test-Path $script:TestStateDir) { Remove-Item $script:TestStateDir -Recurse -Force }
	}

	Context "Nothing to close" {
		It "closes nothing when there is no tracker at all" {
			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			Should -Invoke Wait-WindowsClosed -Times 0
			Should -Invoke Remove-VirtualDesktops -Times 0
		}

		It "closes nothing when the tracker holds no entries" {
			Set-Tracker -Entry @()

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			Should -Invoke Wait-WindowsClosed -Times 0
			Should -Invoke Remove-VirtualDesktops -Times 0
		}

		It "closes nothing when the named workspace is not tracked as open" {
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub'))))

			Close-Workspace -Workspace 'NotOpen' -StatePath $script:TestStatePath

			Should -Invoke Wait-WindowsClosed -Times 0
			Get-TrackedWorkspaceName | Should -Be @('Server')
		}

		It "closes nothing when the interactive menu is cancelled" {
			# [Enter] at the prompt makes Resolve-Selection answer $null, and @($null) is a
			# one-element array holding nothing - a bare count check reads it as a selection and
			# runs the whole teardown against a name that does not exist.
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub'))))
			Mock Resolve-Selection { $null }

			Close-Workspace -StatePath $script:TestStatePath

			Should -Invoke Wait-WindowsClosed -Times 0
			Should -Invoke Remove-VirtualDesktops -Times 0
			Should -Invoke Focus-TerminalTab -Times 0
			Get-TrackedWorkspaceName | Should -Be @('Server')
		}

		It "closes nothing when the menu returns only blank entries" {
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub'))))
			Mock Resolve-Selection { @('', '   ') }

			Close-Workspace -StatePath $script:TestStatePath

			Should -Invoke Wait-WindowsClosed -Times 0
			Should -Invoke Remove-VirtualDesktops -Times 0
			Get-TrackedWorkspaceName | Should -Be @('Server')
		}

		It "offers only the workspaces that are actually open" {
			Set-Tracker -Entry @(
				(New-Entry -Workspace 'Server'),
				(New-Entry -Workspace 'Server' -Alongside -DesktopOffset 5),
				(New-Entry -Workspace 'WinuX')
			)

			Close-Workspace -StatePath $script:TestStatePath

			# One row per INSTANCE: the two Server opens are two separate sets of windows on screen.
			Should -Invoke Resolve-Selection -Times 1 -ParameterFilter {
				@($OptionList).Count -eq 3 -and
				$OptionList -contains 'Server (plain, desktop 1)' -and
				$OptionList -contains 'Server (alongside, desktop 6)' -and
				$OptionList -contains 'WinuX'
			}
		}

		It "leaves a workspace with a single instance labelled by its bare name" {
			# The everyday menu must not gain anything to read just because instance labels exist.
			Set-Tracker -Entry @((New-Entry -Workspace 'Server'), (New-Entry -Workspace 'WinuX' -Alongside -DesktopOffset 2))

			Close-Workspace -StatePath $script:TestStatePath

			Should -Invoke Resolve-Selection -Times 1 -ParameterFilter {
				@($OptionList).Count -eq 2 -and $OptionList -contains 'Server' -and $OptionList -contains 'WinuX'
			}
		}
	}

	Context "Closing windows" {
		It "closes the tracked windows of the selected workspace" {
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Windows @(
						(New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub'),
						(New-WindowRecord -Handle 203 -ProcessId 22 -ProcessName 'Code' -Title 'Repo - VS Code')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(101, 203)
		}

		It "leaves windows belonging to a workspace that stays open alone" {
			Set-Tracker -Entry @(
				(New-Entry -Workspace 'Server' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub'))),
				(New-Entry -Workspace 'WinuX' -Alongside -Windows @((New-WindowRecord -Handle 203 -ProcessId 22 -ProcessName 'Code' -Title 'Repo - VS Code')))
			)

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(101)
		}

		It "skips a window a surviving workspace claims by process and title even when its handle moved" {
			# The single-instance guarantee under a re-spawned window: the surviving entry's
			# recorded handle is stale, so only its process/title identity can protect it.
			Set-Tracker -Entry @(
				(New-Entry -Workspace 'Server' -Windows @((New-WindowRecord -Handle 999 -ProcessId 33 -ProcessName 'Obsidian' -Title 'Vault - Obsidian'))),
				(New-Entry -Workspace 'WinuX' -Alongside -Windows @((New-WindowRecord -Handle 888 -ProcessId 33 -ProcessName 'Obsidian' -Title 'Vault - Obsidian')))
			)

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			@($script:postedWindows).Count | Should -Be 0
		}

		It "closes every tracked instance of a workspace opened more than once" {
			Set-Tracker -Entry @(
				(New-Entry -Workspace 'Server' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub'))),
				(New-Entry -Workspace 'Server' -Alongside -DesktopOffset 3 -Windows @((New-WindowRecord -Handle 203 -ProcessId 22 -ProcessName 'Code' -Title 'Repo - VS Code')))
			)

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(101, 203)
		}

		It "takes a Windows Terminal window down by its tabs, not by WM_CLOSE" {
			# A multi-tab terminal answers WM_CLOSE with a confirmation dialog, so the tab pass
			# goes first and the window disappears with its last tab.
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Windows @(
						(New-WindowRecord -Handle 407 -ProcessId 44 -ProcessName 'WindowsTerminal' -Title 'Server.Api'),
						(New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(101)
			$script:closedTabs | Should -Be @('pwsh', 'Server.Api', 'Server.Ui')
		}

		It "ignores tracked windows that are already gone" {
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Windows @(
						(New-WindowRecord -Handle 555 -ProcessId 55 -ProcessName 'gone' -Title 'closed already'),
						(New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(101)
		}
	}

	Context "The same workspace open twice" {
		# "w example -Browser Chrome" then "w example -Browser Edge -Alongside": one name, two entries,
		# two sets of windows side by side. Each has to be closable on its own.
		BeforeEach {
			$script:desktopOfHandle = @{ '101' = 0; '203' = 5 }
			Mock Get-WindowHandle {
				param($ProcessName, $WindowTitle)
				if ($ProcessName -eq 'WindowsTerminal') { return @($script:liveTerminalWindows) }
				@(
					(New-TestWindow -Handle 101 -ProcessId 11 -ProcessName 'chrome' -Title 'New Tab - Google Chrome'),
					(New-TestWindow -Handle 203 -ProcessId 22 -ProcessName 'msedge' -Title 'New tab - Microsoft Edge')
				)
			}

			$script:twoInstances = @(
				(New-Entry -Workspace 'Example' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'chrome' -Title 'New Tab - Google Chrome'))),
				(New-Entry -Workspace 'Example' -Alongside -DesktopOffset 5 -Windows @((New-WindowRecord -Handle 203 -ProcessId 22 -ProcessName 'msedge' -Title 'New tab - Microsoft Edge')))
			)
		}

		It "closes only the instance whose label was selected" {
			Set-Tracker -Entry $script:twoInstances
			Mock Resolve-Selection { @('Example (alongside, desktop 6)') }

			Close-Workspace -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(203)
		}

		It "keeps the other instance in the tracker" {
			Set-Tracker -Entry $script:twoInstances
			Mock Resolve-Selection { @('Example (alongside, desktop 6)') }

			Close-Workspace -StatePath $script:TestStatePath

			$remaining = @((Get-WorkspaceState -StatePath $script:TestStatePath).Entries)
			$remaining.Count | Should -Be 1
			$remaining[0].Alongside | Should -BeFalse
		}

		It "removes only that instance's desktop" {
			Set-Tracker -Entry $script:twoInstances
			Mock Resolve-Selection { @('Example (alongside, desktop 6)') }

			Close-Workspace -StatePath $script:TestStatePath

			$script:removedDesktopIndexes | Should -Be @(5)
		}

		It "closes the plain instance when that is the one selected" {
			Set-Tracker -Entry $script:twoInstances
			Mock Resolve-Selection { @('Example (plain, desktop 1)') }

			Close-Workspace -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(101)
			$script:removedDesktopIndexes | Should -Be @(0)
		}

		It "closes both when both rows are selected" {
			Set-Tracker -Entry $script:twoInstances
			Mock Resolve-Selection { @('Example (plain, desktop 1)', 'Example (alongside, desktop 6)') }

			Close-Workspace -StatePath $script:TestStatePath

			@($script:postedWindows.Handle | Sort-Object) | Should -Be @(101, 203)
			Get-TrackedWorkspaceName | Should -Be @()
		}

		It "still closes every instance when the bare name is given" {
			# The documented shorthand, and what keeps "cw Example" usable from a script.
			Set-Tracker -Entry $script:twoInstances

			Close-Workspace -Workspace 'Example' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle | Sort-Object) | Should -Be @(101, 203)
		}

		It "does not show the menu when a bare name resolved everything" {
			Set-Tracker -Entry $script:twoInstances

			Close-Workspace -Workspace 'Example' -StatePath $script:TestStatePath

			Should -Invoke Resolve-Selection -Times 0
		}

		It "targets one instance when a full label is passed as an argument" {
			Set-Tracker -Entry $script:twoInstances

			Close-Workspace -Workspace 'Example (plain, desktop 1)' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(101)
		}

		It "closes its own window even when both instances used the same browser" {
			# Both instances then have identically titled windows, which is the survivor-guard trap:
			# a window matched by its own live handle must not be held back by the other instance's.
			Set-Tracker -Entry @(
				(New-Entry -Workspace 'Example' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'chrome' -Title 'New Tab - Google Chrome'))),
				(New-Entry -Workspace 'Example' -Alongside -DesktopOffset 5 -Windows @((New-WindowRecord -Handle 203 -ProcessId 11 -ProcessName 'chrome' -Title 'New Tab - Google Chrome')))
			)
			Mock Get-WindowHandle {
				param($ProcessName, $WindowTitle)
				if ($ProcessName -eq 'WindowsTerminal') { return @($script:liveTerminalWindows) }
				@(
					(New-TestWindow -Handle 101 -ProcessId 11 -ProcessName 'chrome' -Title 'New Tab - Google Chrome'),
					(New-TestWindow -Handle 203 -ProcessId 11 -ProcessName 'chrome' -Title 'New Tab - Google Chrome')
				)
			}
			Mock Resolve-Selection { @('Example (alongside, desktop 6)') }

			Close-Workspace -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(203)
		}

		It "keeps labels unique even when two instances look identical" {
			# Resolve-Selection de-duplicates what it returns, so two rows sharing a label would
			# collapse into one and silently spare an instance.
			Set-Tracker -Entry @(
				(New-Entry -Workspace 'Example' -Alongside -DesktopOffset 5),
				(New-Entry -Workspace 'Example' -Alongside -DesktopOffset 5)
			)

			Close-Workspace -StatePath $script:TestStatePath

			Should -Invoke Resolve-Selection -Times 1 -ParameterFilter {
				@($OptionList).Count -eq 2 -and @($OptionList | Select-Object -Unique).Count -eq 2
			}
		}
	}

	Context "Two workspaces with identically titled windows" {
		# The reported failure. Open WinuX and FuturamaSoft and both have a "YouTube - Mozilla Firefox"
		# and a "New chat - Claude - Mozilla Firefox" window; closing one left its own two on screen,
		# protected by the other workspace's identically titled ones.
		BeforeEach {
			Mock Get-WindowHandle {
				param($ProcessName, $WindowTitle)
				if ($ProcessName -eq 'WindowsTerminal') { return @($script:liveTerminalWindows) }
				@(
					(New-TestWindow -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'YouTube - Mozilla Firefox'),
					(New-TestWindow -Handle 203 -ProcessId 11 -ProcessName 'firefox' -Title 'YouTube - Mozilla Firefox')
				)
			}
		}

		It "closes its own window even though a surviving workspace has the same title" {
			Set-Tracker -Entry @(
				(New-Entry -Workspace 'WinuX' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'YouTube - Mozilla Firefox'))),
				(New-Entry -Workspace 'FuturamaSoft' -Alongside -DesktopOffset 1 -Windows @((New-WindowRecord -Handle 203 -ProcessId 11 -ProcessName 'firefox' -Title 'YouTube - Mozilla Firefox')))
			)

			Close-Workspace -Workspace 'FuturamaSoft' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(203)
		}

		It "closes it in either order" {
			Set-Tracker -Entry @(
				(New-Entry -Workspace 'WinuX' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'YouTube - Mozilla Firefox'))),
				(New-Entry -Workspace 'FuturamaSoft' -Alongside -DesktopOffset 1 -Windows @((New-WindowRecord -Handle 203 -ProcessId 11 -ProcessName 'firefox' -Title 'YouTube - Mozilla Firefox')))
			)

			Close-Workspace -Workspace 'WinuX' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(101)
		}

		It "still protects a surviving workspace's window when the handle went stale" {
			# The guard has to keep working for the case it was written for: a record whose handle is
			# gone is re-resolved by process and title, and that search must not land on a survivor's
			# window.
			Set-Tracker -Entry @(
				(New-Entry -Workspace 'WinuX' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'YouTube - Mozilla Firefox'))),
				(New-Entry -Workspace 'FuturamaSoft' -Alongside -Windows @((New-WindowRecord -Handle 999 -ProcessId 987 -ProcessName 'firefox' -Title 'YouTube - Mozilla Firefox')))
			)

			Close-Workspace -Workspace 'FuturamaSoft' -StatePath $script:TestStatePath

			@($script:postedWindows).Count | Should -Be 0
		}
	}

	Context "The workspace's own virtual desktops" {
		BeforeEach {
			# WinuX on desktop 0, FuturamaSoft alongside on desktop 1, plus an untracked window that is
			# sitting on FuturamaSoft's desktop.
			$script:desktopOfHandle = @{ '101' = 0; '203' = 1; '305' = 1 }
			Mock Get-WindowHandle {
				param($ProcessName, $WindowTitle)
				if ($ProcessName -eq 'WindowsTerminal') { return @($script:liveTerminalWindows) }
				@(
					(New-TestWindow -Handle 101 -ProcessId 11 -ProcessName 'Code' -Title 'WinuX - VS Code'),
					(New-TestWindow -Handle 203 -ProcessId 22 -ProcessName 'Code' -Title 'FuturamaSoft - VS Code'),
					(New-TestWindow -Handle 305 -ProcessId 33 -ProcessName 'firefox' -Title 'opened later - Mozilla Firefox')
				)
			}

			# Built here rather than in the Context body: Pester evaluates that during discovery, so a
			# variable set there is not the one an It block sees while it runs.
			$script:twoWorkspaceEntries = @(
				(New-Entry -Workspace 'WinuX' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'Code' -Title 'WinuX - VS Code'))),
				(New-Entry -Workspace 'FuturamaSoft' -Alongside -DesktopOffset 1 -Windows @((New-WindowRecord -Handle 203 -ProcessId 22 -ProcessName 'Code' -Title 'FuturamaSoft - VS Code')))
			)
		}

		It "closes an untracked window sitting on them" {
			# Nothing recorded window 305 - it appeared after the open - but it is on the workspace's
			# desktop, which is what makes it the workspace's.
			Set-Tracker -Entry $script:twoWorkspaceEntries

			Close-Workspace -Workspace 'FuturamaSoft' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(203, 305)
		}

		It "leaves a window on a surviving workspace's desktop alone" {
			Set-Tracker -Entry $script:twoWorkspaceEntries

			Close-Workspace -Workspace 'FuturamaSoft' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Not -Contain 101
		}

		It "removes them by index rather than waiting for them to look empty" {
			Set-Tracker -Entry $script:twoWorkspaceEntries

			Close-Workspace -Workspace 'FuturamaSoft' -StatePath $script:TestStatePath

			$script:removedDesktopIndexes | Should -Be @(1)
		}

		It "never removes a desktop a surviving workspace is on" {
			Set-Tracker -Entry $script:twoWorkspaceEntries

			Close-Workspace -Workspace 'FuturamaSoft' -StatePath $script:TestStatePath

			$script:removedDesktopIndexes | Should -Not -Contain 0
		}

		It "removes desktop 0 when the workspace that lands there is the one closing" {
			# 0 is falsy, so a truthiness check anywhere on this path would lose the plain workspace's
			# only desktop.
			Set-Tracker -Entry $script:twoWorkspaceEntries

			Close-Workspace -Workspace 'WinuX' -StatePath $script:TestStatePath

			$script:removedDesktopIndexes | Should -Be @(0)
		}

		It "removes every closed workspace's desktops when several go at once" {
			Set-Tracker -Entry $script:twoWorkspaceEntries

			Close-Workspace -Workspace 'WinuX', 'FuturamaSoft' -StatePath $script:TestStatePath

			@($script:removedDesktopIndexes | Sort-Object) | Should -Be @(0, 1)
		}

		It "still sweeps desktops it emptied without ever having a window on them" {
			Set-Tracker -Entry $script:twoWorkspaceEntries

			Close-Workspace -Workspace 'FuturamaSoft' -StatePath $script:TestStatePath

			Should -Invoke Remove-VirtualDesktops -Times 1 -ParameterFilter { $EmptyOnly }
		}

		It "removes nothing on a dry run" {
			Set-Tracker -Entry $script:twoWorkspaceEntries

			Close-Workspace -Workspace 'FuturamaSoft' -StatePath $script:TestStatePath -WhatIf

			$script:removedDesktopIndexes | Should -BeNullOrEmpty
			Should -Invoke Remove-VirtualDesktops -Times 0
		}

		It "does not close a Windows Terminal window merely for standing on them" {
			# Closing a terminal window wholesale would take tabs the workspace never opened; the tab
			# pass owns that decision.
			$script:desktopOfHandle['407'] = 1
			Set-Tracker -Entry $script:twoWorkspaceEntries

			Close-Workspace -Workspace 'FuturamaSoft' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Not -Contain 407
		}
	}

	Context "Re-resolving stale handles" {
		It "follows a window that its process recreated under a new handle" {
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Windows @(
						(New-WindowRecord -Handle 999 -ProcessId 33 -ProcessName 'Obsidian' -Title 'Old title')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(305)
		}

		It "falls back to the exact process name and title when the process restarted too" {
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Windows @(
						(New-WindowRecord -Handle 999 -ProcessId 987 -ProcessName 'Obsidian' -Title 'Vault - Obsidian')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(305)
		}

		It "does not match on a title alone when the record names no process" {
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Windows @(
						(New-WindowRecord -Handle 999 -ProcessId 0 -ProcessName '' -Title 'Vault - Obsidian')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			@($script:postedWindows).Count | Should -Be 0
		}

		It "does not match a different title in the same process name" {
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Windows @(
						(New-WindowRecord -Handle 999 -ProcessId 987 -ProcessName 'Obsidian' -Title 'A different vault')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			@($script:postedWindows).Count | Should -Be 0
		}
	}

	Context "Closing terminal tabs" {
		It "closes the tracked tabs of the selected workspace" {
			$script:liveTabTitles = @('pwsh', 'Server.Api', 'Server.Ui')
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -TerminalTabs @(
						(New-TabRecord -WindowHandle 407 -Title 'Server.Api'),
						(New-TabRecord -WindowHandle 407 -Title 'Server.Ui')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			$script:closedTabs | Should -Be @('Server.Api', 'Server.Ui')
		}

		It "leaves tabs the workspace did not open alone" {
			$script:liveTabTitles = @('pwsh', 'Server.Api')
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -TerminalTabs @((New-TabRecord -WindowHandle 407 -Title 'Server.Api'))))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			$script:closedTabs | Should -Be @('Server.Api')
		}

		It "skips a tracked tab that is no longer on the tab strip" {
			$script:liveTabTitles = @('pwsh')
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -TerminalTabs @((New-TabRecord -WindowHandle 407 -Title 'Server.Api'))))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			Should -Invoke Close-WindowsTerminalTab -Times 0
		}

		It "reads each terminal window's tab strip once rather than once per tab" {
			$script:liveTabTitles = @('Server.Api', 'Server.Ui', 'Server.Web')
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -TerminalTabs @(
						(New-TabRecord -WindowHandle 407 -Title 'Server.Api'),
						(New-TabRecord -WindowHandle 407 -Title 'Server.Ui'),
						(New-TabRecord -WindowHandle 407 -Title 'Server.Web')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			Should -Invoke Get-WindowsTerminalTabTitles -Times 1
		}
	}

	Context "Terminal windows the workspace opened" {
		It "closes every tab of a window it opened, including ones it never recorded" {
			# The reported -Alongside failure: the new terminal window was recorded but the UI
			# Automation read of its tab strip came back empty as the open finished (a window the
			# layout pass had moved to another virtual desktop may not expose one). Owning the
			# window is what closes it; the tab records only refine which tabs to take.
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Alongside -DesktopOffset 3 -Windows @(
						(New-WindowRecord -Handle 407 -ProcessId 44 -ProcessName 'WindowsTerminal' -Title 'Server.Api')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			$script:closedTabs | Should -Be @('pwsh', 'Server.Api', 'Server.Ui')
		}

		It "closes the window directly when its tab strip cannot be read at all" {
			$script:tabsUnreadable = $true
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Alongside -Windows @(
						(New-WindowRecord -Handle 407 -ProcessId 44 -ProcessName 'WindowsTerminal' -Title 'Server.Api')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			Should -Invoke Close-WindowsTerminalTab -Times 0
			@($script:postedWindows.Handle) | Should -Be @(407)
		}

		It "closes a window that outlived the tab pass" {
			# Tabs report success but the window is still there - it must not be left running.
			Mock Close-WindowsTerminalTab { param($WindowHandle, $TabTitle) $script:closedTabs += $TabTitle; $true }
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Alongside -Windows @(
						(New-WindowRecord -Handle 407 -ProcessId 44 -ProcessName 'WindowsTerminal' -Title 'Server.Api')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			@($script:postedWindows.Handle) | Should -Be @(407)
		}

		It "leaves untracked tabs alone in a window it did not open" {
			# The everyday case: project tabs opened into the terminal already on screen. The
			# window is not the workspace's, so only its recorded tabs go.
			$script:liveTabTitles = @('pwsh', 'Server.Api', 'unrelated work')
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -TerminalTabs @(
						(New-TabRecord -WindowHandle 407 -Title 'Server.Api')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			$script:closedTabs | Should -Be @('Server.Api')
			@($script:postedWindows).Count | Should -Be 0
		}

		It "reports rather than force-closes a shared window whose tab strip cannot be read" {
			$script:tabsUnreadable = $true
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -TerminalTabs @(
						(New-TabRecord -WindowHandle 407 -Title 'Server.Api')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			@($script:postedWindows).Count | Should -Be 0
			Should -Invoke Write-LogList -Times 1
		}
	}

	Context "Terminals parked on another virtual desktop" {
		BeforeEach {
			# The reported failure: Windows Terminal composes its tab strip only while its desktop
			# is on screen, and the layout pass has moved the workspace's terminal to the
			# workspace's own desktop, so the first read comes back with nothing.
			$script:tabsNeedDesktop = $true
		}

		It "brings the desktop on screen and closes the tab that was unreachable" {
			$script:liveTabTitles = @('pwsh', 'Dotfiles.ROOT')
			Set-Tracker -Entry @((New-Entry -Workspace 'Dotfiles' -TerminalTabs @(
						(New-TabRecord -WindowHandle 407 -Title 'Dotfiles.ROOT')
					)))

			Close-Workspace -Workspace 'Dotfiles' -StatePath $script:TestStatePath

			$script:closedTabs | Should -Be @('Dotfiles.ROOT')
			$script:desktopSwitches | Should -Contain 'window:407'
		}

		It "reports nothing as refused once the tab is reachable" {
			$script:liveTabTitles = @('pwsh', 'Dotfiles.ROOT')
			Set-Tracker -Entry @((New-Entry -Workspace 'Dotfiles' -TerminalTabs @(
						(New-TabRecord -WindowHandle 407 -Title 'Dotfiles.ROOT')
					)))

			Close-Workspace -Workspace 'Dotfiles' -StatePath $script:TestStatePath

			Should -Invoke Write-LogList -Times 0
		}

		It "puts the view back before the desktop sweep" {
			$script:liveTabTitles = @('pwsh', 'Dotfiles.ROOT')
			Set-Tracker -Entry @((New-Entry -Workspace 'Dotfiles' -TerminalTabs @(
						(New-TabRecord -WindowHandle 407 -Title 'Dotfiles.ROOT')
					)))

			Close-Workspace -Workspace 'Dotfiles' -StatePath $script:TestStatePath

			$script:desktopSwitches | Should -Be @('window:407', 'restore:1')
			Should -Invoke Remove-VirtualDesktops -Times 1
		}

		It "switches once for several tabs in the same window" {
			$script:liveTabTitles = @('pwsh', 'Server.Api', 'Server.Ui')
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -TerminalTabs @(
						(New-TabRecord -WindowHandle 407 -Title 'Server.Api'),
						(New-TabRecord -WindowHandle 407 -Title 'Server.Ui')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			@($script:desktopSwitches | Where-Object { $_ -like 'window:*' }).Count | Should -Be 1
			$script:closedTabs | Should -Be @('Server.Api', 'Server.Ui')
		}

		It "does not switch desktops for a terminal that is already on screen" {
			$script:tabsNeedDesktop = $false
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -TerminalTabs @(
						(New-TabRecord -WindowHandle 407 -Title 'Server.Api')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			Should -Invoke Ensure-DesktopVisible -Times 0
		}

		It "reports the tab as refused when the strip is unreadable even on screen" {
			$script:tabsUnreadable = $true
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -TerminalTabs @(
						(New-TabRecord -WindowHandle 407 -Title 'Server.Api')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			Should -Invoke Close-WindowsTerminalTab -Times 0
			Should -Invoke Write-LogList -Times 1
		}
	}

	Context "The calling tab" {
		BeforeEach {
			$script:liveTabTitles = @('Server.Api', 'Server.Ui')
			Mock Resolve-HostingTerminalTab {
				[pscustomobject]@{ Handle = [IntPtr]407; ProcessId = 44; TabTitle = 'Server.Api' }
			}
		}

		It "closes its own tab last, through the process-exit seam" {
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -TerminalTabs @(
						(New-TabRecord -WindowHandle 407 -Title 'Server.Api'),
						(New-TabRecord -WindowHandle 407 -Title 'Server.Ui')
					)))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			# Its own tab is never closed in the normal pass - that would kill the flow mid-run.
			$script:closedTabs | Should -Be @('Server.Ui')
			Should -Invoke Invoke-TerminateWindowsTerminalTabsExit -Times 1
			Should -Invoke Focus-TerminalTab -Times 0
		}

		It "writes the tracker before exiting, since the exit skips everything after it" {
			Set-Tracker -Entry @(
				(New-Entry -Workspace 'Server' -TerminalTabs @((New-TabRecord -WindowHandle 407 -Title 'Server.Api'))),
				(New-Entry -Workspace 'WinuX')
			)

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			Get-TrackedWorkspaceName | Should -Be @('WinuX')
		}

		It "returns focus to the terminal instead when its own tab is not part of the workspace" {
			Mock Resolve-HostingTerminalTab {
				[pscustomobject]@{ Handle = [IntPtr]407; ProcessId = 44; TabTitle = 'unrelated tab' }
			}
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -TerminalTabs @((New-TabRecord -WindowHandle 407 -Title 'Server.Api'))))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			Should -Invoke Focus-TerminalTab -Times 1
			Should -Invoke Invoke-TerminateWindowsTerminalTabsExit -Times 0
		}

		It "does not treat a same-named tab in a different terminal window as its own" {
			Mock Resolve-HostingTerminalTab {
				[pscustomobject]@{ Handle = [IntPtr]909; ProcessId = 99; TabTitle = 'Server.Api' }
			}
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -TerminalTabs @((New-TabRecord -WindowHandle 407 -Title 'Server.Api'))))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			$script:closedTabs | Should -Be @('Server.Api')
			Should -Invoke Invoke-TerminateWindowsTerminalTabsExit -Times 0
		}
	}

	Context "Aftermath" {
		It "removes the closed workspace from the tracker and keeps the rest" {
			Set-Tracker -Entry @(
				(New-Entry -Workspace 'Server' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub'))),
				(New-Entry -Workspace 'WinuX' -Alongside -Windows @((New-WindowRecord -Handle 203 -ProcessId 22 -ProcessName 'Code' -Title 'Repo - VS Code')))
			)

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			Get-TrackedWorkspaceName | Should -Be @('WinuX')
		}

		It "is a clean no-op the second time" {
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub'))))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath
			$script:postedWindows = @()
			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			@($script:postedWindows).Count | Should -Be 0
			Should -Invoke Remove-VirtualDesktops -Times 1
		}

		It "sweeps up the emptied virtual desktops" {
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub'))))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			Should -Invoke Remove-VirtualDesktops -Times 1 -ParameterFilter { $EmptyOnly }
		}

		It "reports a window that refused to close and still finishes the teardown" {
			Mock Wait-WindowsClosed {
				param($Window, $TimeoutMilliseconds, $PollIntervalMilliseconds)
				$script:postedWindows = @($Window)
				@($Window)
			}
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub'))))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath

			Should -Invoke Write-LogWarning -Times 1
			Should -Invoke Remove-VirtualDesktops -Times 1
			Get-TrackedWorkspaceName | Should -Be @()
		}
	}

	Context "Dry run" {
		It "closes nothing, removes no desktops, and leaves the tracker untouched" {
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' `
						-Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub')) `
						-TerminalTabs @((New-TabRecord -WindowHandle 407 -Title 'Server.Api'))))
			$script:liveTabTitles = @('Server.Api')

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath -WhatIf

			@($script:postedWindows).Count | Should -Be 0
			Should -Invoke Close-WindowsTerminalTab -Times 0
			Should -Invoke Remove-VirtualDesktops -Times 0
			Get-TrackedWorkspaceName | Should -Be @('Server')
		}

		It "does not exit the shell when its own tab would have been closed" {
			Mock Resolve-HostingTerminalTab {
				[pscustomobject]@{ Handle = [IntPtr]407; ProcessId = 44; TabTitle = 'Server.Api' }
			}
			$script:liveTabTitles = @('Server.Api')
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -TerminalTabs @((New-TabRecord -WindowHandle 407 -Title 'Server.Api'))))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath -WhatIf

			Should -Invoke Invoke-TerminateWindowsTerminalTabsExit -Times 0
		}

		It "does not steal focus" {
			Set-Tracker -Entry @((New-Entry -Workspace 'Server' -Windows @((New-WindowRecord -Handle 101 -ProcessId 11 -ProcessName 'firefox' -Title 'GitHub'))))

			Close-Workspace -Workspace 'Server' -StatePath $script:TestStatePath -WhatIf

			Should -Invoke Focus-TerminalTab -Times 0
		}
	}
}
