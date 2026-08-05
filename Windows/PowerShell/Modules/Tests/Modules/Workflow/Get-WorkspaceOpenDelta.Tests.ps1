#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. (Join-Path $ModuleRoot "Workflow\Functions\Get-WorkspaceOpenDelta.ps1")

	function Get-WindowHandle { param($ProcessName, $WindowTitle) @() }
	function Get-TerminalTabSnapshot { param([switch]$EnsureVisible) @{} }

	function New-TestWindow {
		param($Handle, $ProcessId, $ProcessName, $Title)
		[PSCustomObject]@{
			Handle      = [IntPtr]$Handle
			ProcessId   = $ProcessId
			ProcessName = $ProcessName
			Title       = $Title
		}
	}

	function New-HandleSet {
		param([int[]]$Handle)
		$set = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
		foreach ($item in $Handle) { [void]$set.Add([IntPtr]$item) }
		$set
	}

	# Builds a tab snapshot with Int64 keys, which is what the real Get-TerminalTabSnapshot produces
	# (IntPtr.ToInt64). It matters because a hashtable lookup is TYPE-exact: an Int32 key never matches
	# an Int64 one, so a snapshot mocked with bare integer literals would not exercise the key type the
	# diff actually meets in production.
	function New-TabSnapshot {
		param([hashtable]$Window)
		$snapshot = @{}
		foreach ($key in $Window.Keys) { $snapshot[[int64]$key] = @($Window[$key]) }
		$snapshot
	}
}

Describe "Get-WorkspaceOpenDelta" {
	BeforeEach {
		Mock Get-TerminalTabSnapshot { param([switch]$EnsureVisible) @{} }

		# No exclusions unless a test opts in, so the adoption tests below start from "adopt
		# everything" and each exclusion assertion is visibly the thing that changed.
		$script:Configuration = @{ Universal = @{ VisibleWindowExclusions = @() } }
	}

	Context "Window ownership" {
		BeforeEach {
			Mock Get-WindowHandle {
				@(
					(New-TestWindow -Handle 1 -ProcessId 11 -ProcessName 'Obsidian' -Title 'Vault - Obsidian'),
					(New-TestWindow -Handle 2 -ProcessId 22 -ProcessName 'firefox' -Title 'GitHub'),
					(New-TestWindow -Handle 3 -ProcessId 33 -ProcessName 'Code' -Title 'Repo - VS Code')
				)
			}
		}

		It "records only the windows that appeared during the open" {
			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles (New-HandleSet 1)

			@($delta.Windows).Count | Should -Be 2
			@($delta.Windows.Handle) | Should -Be @(2, 3)
		}

		It "leaves an already-running single-instance app out of the entry" {
			# The requirement this exists for: Obsidian was launched by an earlier workspace, so
			# this open created no window for it and closing this workspace must not close it.
			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles (New-HandleSet 1)

			@($delta.Windows | Where-Object { $_.ProcessName -eq 'Obsidian' }) | Should -BeNullOrEmpty
		}

		It "records everything on screen when nothing existed before" {
			$delta = Get-WorkspaceOpenDelta -Workspace 'Server'

			@($delta.Windows).Count | Should -Be 3
		}

		It "records nothing when the open created no window" {
			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles (New-HandleSet 1, 2, 3)

			@($delta.Windows).Count | Should -Be 0
		}

		It "keeps the process fingerprint and title so a stale handle can be re-resolved later" {
			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles (New-HandleSet 1, 3)

			$delta.Windows[0].Handle | Should -Be 2
			$delta.Windows[0].ProcessId | Should -Be 22
			$delta.Windows[0].ProcessName | Should -Be 'firefox'
			$delta.Windows[0].Title | Should -Be 'GitHub'
		}

		It "accepts the pre-open capture as window objects as well as as a handle set" {
			$asObjects = @((New-TestWindow -Handle 1), (New-TestWindow -Handle 2))

			@((Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles $asObjects).Windows).Count | Should -Be 1
		}

		It "claims everything on screen when adopting, including an app that was already running" {
			# The reported failure: Open-ClaudeDesktop reports "already running", creates no window,
			# so a pure diff records nothing and Close-Workspace can never touch it. Worse, that
			# state feeds itself - it survives one teardown and is already running at every open
			# after, so it is never recorded again.
			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles (New-HandleSet 1) -AdoptUnclaimed

			@($delta.Windows).Count | Should -Be 3
			@($delta.Windows | Where-Object { $_.ProcessName -eq 'Obsidian' }) | Should -Not -BeNullOrEmpty
		}

		It "still claims only what it created when not adopting" {
			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles (New-HandleSet 1)

			@($delta.Windows).Count | Should -Be 2
		}

		It "ignores windows with no usable handle" {
			Mock Get-WindowHandle {
				@(
					(New-TestWindow -Handle 0 -ProcessId 11 -ProcessName 'ghost' -Title 'no handle'),
					(New-TestWindow -Handle 2 -ProcessId 22 -ProcessName 'firefox' -Title 'GitHub')
				)
			}

			$delta = Get-WorkspaceOpenDelta -Workspace 'Server'

			@($delta.Windows).Count | Should -Be 1
			$delta.Windows[0].Handle | Should -Be 2
		}
	}

	Context "What adoption may not claim" {
		BeforeEach {
			Mock Get-WindowHandle {
				@(
					(New-TestWindow -Handle 1 -ProcessId 11 -ProcessName 'WindowsTerminal' -Title 'pwsh'),
					(New-TestWindow -Handle 2 -ProcessId 22 -ProcessName 'Rainmeter' -Title 'Rainmeter'),
					(New-TestWindow -Handle 3 -ProcessId 33 -ProcessName 'claude' -Title 'Claude')
				)
			}

			$script:Configuration = @{
				Universal = @{ VisibleWindowExclusions = @('Rainmeter', 'WindowsTerminal') }
			}
		}

		It "leaves an excluded process out of what it adopts" {
			# Universal.VisibleWindowExclusions is the repository's answer to "what does a teardown
			# never touch". Adoption has to honour it, or a plain open takes ownership of the very
			# terminal window it was typed in and closing that workspace closes the shell.
			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles (New-HandleSet 1, 2, 3) -AdoptUnclaimed

			@($delta.Windows.ProcessName) | Should -Be @('claude')
		}

		It "matches the exclusion list regardless of case" {
			$script:Configuration.Universal.VisibleWindowExclusions = @('rainmeter', 'windowsterminal')

			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles (New-HandleSet 1, 2, 3) -AdoptUnclaimed

			@($delta.Windows.ProcessName) | Should -Be @('claude')
		}

		It "still records an excluded process when this open actually created its window" {
			# The exclusion limits what adoption reaches for; it never overrides the diff, which
			# already proves the window belongs to this workspace.
			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles (New-HandleSet 3) -AdoptUnclaimed

			@($delta.Windows.ProcessName) | Should -Contain 'WindowsTerminal'
			@($delta.Windows.ProcessName) | Should -Contain 'Rainmeter'
		}

		It "adopts an excluded process once it is taken off the list" {
			$script:Configuration.Universal.VisibleWindowExclusions = @()

			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles (New-HandleSet 1, 2, 3) -AdoptUnclaimed

			@($delta.Windows).Count | Should -Be 3
		}

		It "adopts everything when no exclusions are configured at all" {
			$script:Configuration = @{}

			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles (New-HandleSet 1, 2, 3) -AdoptUnclaimed

			@($delta.Windows).Count | Should -Be 3
		}

		It "records only the tabs it created while WindowsTerminal is excluded" {
			# Excluding the terminal from window adoption but still adopting its tabs would claim the
			# leftover tabs of unrelated work one by one - the same greed by another route.
			Mock Get-TerminalTabSnapshot { New-TabSnapshot -Window @{ 777 = @('pwsh', 'Server.Api') } }

			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingTerminalTabs (New-TabSnapshot -Window @{ 777 = @('pwsh') }) -AdoptUnclaimed

			@($delta.TerminalTabs.Title) | Should -Be @('Server.Api')
		}

		It "adopts every tab on screen once WindowsTerminal is off the list" {
			$script:Configuration.Universal.VisibleWindowExclusions = @('Rainmeter')
			Mock Get-TerminalTabSnapshot { New-TabSnapshot -Window @{ 777 = @('pwsh', 'Server.Api') } }

			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingTerminalTabs (New-TabSnapshot -Window @{ 777 = @('pwsh') }) -AdoptUnclaimed

			@($delta.TerminalTabs.Title) | Should -Be @('pwsh', 'Server.Api')
		}

		It "ignores the exclusion list entirely when not adopting" {
			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles (New-HandleSet 3)

			@($delta.Windows.ProcessName) | Should -Be @('WindowsTerminal', 'Rainmeter')
		}
	}

	Context "Terminal tab ownership" {
		BeforeEach {
			Mock Get-WindowHandle { @() }
		}

		It "records only the tabs that appeared, per terminal window" {
			Mock Get-TerminalTabSnapshot { New-TabSnapshot -Window @{ 777 = @('pwsh', 'Server.Api', 'Server.Ui') } }

			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingTerminalTabs (New-TabSnapshot -Window @{ 777 = @('pwsh') })

			@($delta.TerminalTabs.Title) | Should -Be @('Server.Api', 'Server.Ui')
			@($delta.TerminalTabs.WindowHandle) | Should -Be @(777, 777)
		}

		It "counts duplicate titles rather than differencing them as a set" {
			# A second tab named the same as an existing one is still a new tab; set subtraction
			# would drop it and leave it running after the workspace is closed.
			Mock Get-TerminalTabSnapshot { New-TabSnapshot -Window @{ 777 = @('Server.Api', 'Server.Api') } }

			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingTerminalTabs (New-TabSnapshot -Window @{ 777 = @('Server.Api') })

			@($delta.TerminalTabs).Count | Should -Be 1
			$delta.TerminalTabs[0].Title | Should -Be 'Server.Api'
		}

		It "treats every tab of a terminal window that did not exist before as new" {
			Mock Get-TerminalTabSnapshot { New-TabSnapshot -Window @{ 777 = @('pwsh'); 888 = @('Server.Api', 'Server.Ui') } }

			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingTerminalTabs (New-TabSnapshot -Window @{ 777 = @('pwsh') })

			@($delta.TerminalTabs).Count | Should -Be 2
			@($delta.TerminalTabs.WindowHandle | Select-Object -Unique) | Should -Be 888
		}

		It "records nothing when the tab strip is unchanged" {
			Mock Get-TerminalTabSnapshot { New-TabSnapshot -Window @{ 777 = @('pwsh', 'Server.Api') } }

			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingTerminalTabs (New-TabSnapshot -Window @{ 777 = @('pwsh', 'Server.Api') })

			@($delta.TerminalTabs).Count | Should -Be 0
		}

		It "claims every tab on screen when adopting" {
			Mock Get-TerminalTabSnapshot { New-TabSnapshot -Window @{ 777 = @('pwsh', 'Server.Api', 'Server.Ui') } }

			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingTerminalTabs (New-TabSnapshot -Window @{ 777 = @('pwsh') }) -AdoptUnclaimed

			@($delta.TerminalTabs.Title) | Should -Be @('pwsh', 'Server.Api', 'Server.Ui')
		}

		It "matches the pre-open snapshot whatever numeric type its keys are" {
			# A hashtable lookup is TYPE-exact, so an Int32 key never matches the Int64 one the real
			# snapshot produces. Unnormalised, a caller-built map keyed with bare integer literals
			# would match nothing, every tab on screen would read as newly created, and an adopting
			# open would claim tabs it never opened.
			Mock Get-TerminalTabSnapshot { New-TabSnapshot -Window @{ 777 = @('pwsh', 'Server.Api') } }

			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingTerminalTabs @{ 777 = @('pwsh') }

			@($delta.TerminalTabs.Title) | Should -Be @('Server.Api')
		}

		It "reads terminals the layout pass has already parked on other desktops" {
			# This runs at the end of an open, when the workspace's terminal has been moved onto
			# one of the workspace's own desktops - and Windows Terminal shows no tab strip while
			# its desktop is off screen. Without asking for it to be made visible the terminal
			# reads as having no tabs and none of the workspace's tabs are ever recorded.
			Get-WorkspaceOpenDelta -Workspace 'Server' | Out-Null

			Should -Invoke Get-TerminalTabSnapshot -Times 1 -ParameterFilter { $EnsureVisible }
		}
	}

	Context "Entry shape" {
		BeforeEach {
			Mock Get-WindowHandle { @() }
		}

		It "carries the mode and offset the open ran with" {
			$delta = Get-WorkspaceOpenDelta -Workspace 'Server' -DesktopOffset 3 -Alongside

			$delta.Workspace | Should -Be 'Server'
			$delta.Alongside | Should -BeTrue
			$delta.DesktopOffset | Should -Be 3
		}

		It "defaults to a plain open at offset zero" {
			$delta = Get-WorkspaceOpenDelta -Workspace 'Server'

			$delta.Alongside | Should -BeFalse
			$delta.DesktopOffset | Should -Be 0
		}

		It "stamps a round-trippable open time" {
			$delta = Get-WorkspaceOpenDelta -Workspace 'Server'

			{ [DateTimeOffset]::ParseExact($delta.OpenedUtc, 'o', [System.Globalization.CultureInfo]::InvariantCulture,
					[System.Globalization.DateTimeStyles]::RoundtripKind) } | Should -Not -Throw
		}
	}
}
