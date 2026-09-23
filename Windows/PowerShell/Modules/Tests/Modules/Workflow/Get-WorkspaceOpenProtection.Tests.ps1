#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Format-WorkspaceStateContent.ps1"
	. "$FunctionsPath\Get-WorkspaceState.ps1"
	. "$FunctionsPath\Get-WorkspaceOpenProtection.ps1"
	. "$FunctionsPath\Resolve-TrackedWorkspaceWindow.ps1"

	$script:TestStateDir = Join-Path $env:TEMP ("WorkspaceOpenProtectionTests_" + $PID)
	$script:TestStatePath = Join-Path $script:TestStateDir "OpenWorkspaces.txt"

	function Get-WorkspaceStatePath { $script:TestStatePath }
	function Get-WindowHandle { param($ProcessName, $WindowTitle) @() }
	function Clear-WindowCache { }

	function New-TestWindow {
		param($Handle, $ProcessId, $ProcessName, $Title)
		[PSCustomObject]@{
			Handle      = [IntPtr]$Handle
			ProcessId   = $ProcessId
			ProcessName = $ProcessName
			Title       = $Title
		}
	}

	function New-TestEntry {
		param($Workspace, [switch]$Alongside, $DesktopOffset = 0, $Windows = @())
		[ordered]@{
			Workspace     = $Workspace
			Alongside     = [bool]$Alongside
			DesktopOffset = $DesktopOffset
			OpenedUtc     = '2026-08-26T09:00:00.0000000+00:00'
			ShellPid      = 4242
			Windows       = $Windows
			TerminalTabs  = @()
		}
	}

	function New-TestRecord {
		param($Handle, $ProcessId = 0, $ProcessName = '', $Title = '')
		[ordered]@{ Handle = [int64]$Handle; ProcessId = [int64]$ProcessId; ProcessName = $ProcessName; Title = $Title }
	}

	# Writes a REAL tracker file the way Save-WorkspaceState does, so the function under test
	# exercises the same parse it meets in production instead of a mocked state object.
	function Write-TestState {
		param($Entry)
		Set-Content -LiteralPath $script:TestStatePath -Value (Format-WorkspaceStateContent -Entry @($Entry)) -NoNewline -Encoding UTF8
	}
}

Describe "Get-WorkspaceOpenProtection" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Get-WindowHandle { @() }
		Mock Clear-WindowCache { }

		if (Test-Path $script:TestStateDir) { Remove-Item $script:TestStateDir -Recurse -Force }
		New-Item -ItemType Directory -Path $script:TestStateDir -Force | Out-Null
	}

	AfterEach {
		if (Test-Path $script:TestStateDir) { Remove-Item $script:TestStateDir -Recurse -Force }
	}

	Context "Nothing to preserve" {
		It "returns null when there is no tracker at all" {
			Get-WorkspaceOpenProtection -StatePath $script:TestStatePath | Should -BeNullOrEmpty
		}

		It "returns null without enumerating windows when nothing alongside is tracked" {
			# The common case - a machine that never opens alongside - must pay one file parse
			# and nothing else. Enumerating every window on screen here would tax every plain
			# open for a feature it is not using.
			Write-TestState -Entry @((New-TestEntry -Workspace 'Server' -Windows @((New-TestRecord -Handle 1))))

			Get-WorkspaceOpenProtection -StatePath $script:TestStatePath | Should -BeNullOrEmpty

			Should -Invoke Get-WindowHandle -Times 0
		}

		It "returns null when every window of the alongside entry is dead" {
			# The workspace is gone, so there is nothing left to protect - and preserving its
			# entry would keep an unclosable ghost in the tracker forever.
			Write-TestState -Entry @(
				(New-TestEntry -Workspace 'WinuX' -Alongside -DesktopOffset 3 -Windows @(
					(New-TestRecord -Handle 50 -ProcessId 5 -ProcessName 'firefox' -Title 'Gone')
				))
			)

			Get-WorkspaceOpenProtection -StatePath $script:TestStatePath | Should -BeNullOrEmpty
		}

		It "never preserves a plain entry, however alive its windows are" {
			# A plain rerun replaces the plain session by design - only alongside instances are
			# additions worth protecting.
			Mock Get-WindowHandle { @((New-TestWindow -Handle 1 -ProcessId 11 -ProcessName 'firefox' -Title 'Plain')) }
			Write-TestState -Entry @(
				(New-TestEntry -Workspace 'Server' -Windows @(
					(New-TestRecord -Handle 1 -ProcessId 11 -ProcessName 'firefox' -Title 'Plain')
				))
			)

			Get-WorkspaceOpenProtection -StatePath $script:TestStatePath | Should -BeNullOrEmpty
		}
	}

	Context "Preserving live alongside workspaces" {
		It "preserves an alongside entry with a live window and returns its resolved handles" {
			Mock Get-WindowHandle {
				@(
					(New-TestWindow -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'Alongside browser'),
					(New-TestWindow -Handle 61 -ProcessId 7 -ProcessName 'Code' -Title 'Alongside editor')
				)
			}
			Write-TestState -Entry @(
				(New-TestEntry -Workspace 'WinuX' -Alongside -DesktopOffset 3 -Windows @(
					(New-TestRecord -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'Alongside browser'),
					(New-TestRecord -Handle 61 -ProcessId 7 -ProcessName 'Code' -Title 'Alongside editor')
				))
			)

			$protection = Get-WorkspaceOpenProtection -StatePath $script:TestStatePath

			$protection | Should -Not -BeNullOrEmpty
			@($protection.Entries).Count | Should -Be 1
			$protection.Entries[0].Workspace | Should -Be 'WinuX'
			$protection.WindowHandles.Count | Should -Be 2
			$protection.WindowHandles.Contains([IntPtr]60) | Should -BeTrue
			$protection.WindowHandles.Contains([IntPtr]61) | Should -BeTrue
		}

		It "does not preserve the alongside instance of a workspace being opened, so the plain open adopts it" {
			Mock Get-WindowHandle {
				@((New-TestWindow -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'Server browser'))
			}
			Write-TestState -Entry @(
				(New-TestEntry -Workspace 'Server' -Alongside -DesktopOffset 3 -Windows @(
					(New-TestRecord -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'Server browser')
				))
			)

			Get-WorkspaceOpenProtection -StatePath $script:TestStatePath -Opening 'server' | Should -BeNullOrEmpty
			Should -Invoke Get-WindowHandle -Times 0
		}

		It "still preserves other workspaces' alongside instances when one of them is being opened" {
			Mock Get-WindowHandle {
				@(
					(New-TestWindow -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'Server browser'),
					(New-TestWindow -Handle 70 -ProcessId 8 -ProcessName 'Code' -Title 'WinuX editor')
				)
			}
			Write-TestState -Entry @(
				(New-TestEntry -Workspace 'Server' -Alongside -DesktopOffset 3 -Windows @(
					(New-TestRecord -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'Server browser')
				)),
				(New-TestEntry -Workspace 'WinuX' -Alongside -DesktopOffset 6 -Windows @(
					(New-TestRecord -Handle 70 -ProcessId 8 -ProcessName 'Code' -Title 'WinuX editor')
				))
			)

			$protection = Get-WorkspaceOpenProtection -StatePath $script:TestStatePath -Opening 'Server', 'Other'

			@($protection.Entries).Count | Should -Be 1
			$protection.Entries[0].Workspace | Should -Be 'WinuX'
			$protection.WindowHandles.Count | Should -Be 1
			$protection.WindowHandles.Contains([IntPtr]70) | Should -BeTrue
			$protection.WindowHandles.Contains([IntPtr]60) | Should -BeFalse
		}

		It "carries the preserved entry forward verbatim, dead records included" {
			# One live window is enough to prove the workspace is standing; the entry travels
			# whole, the same staleness Close-Workspace already tolerates.
			Mock Get-WindowHandle { @((New-TestWindow -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'Live')) }
			Write-TestState -Entry @(
				(New-TestEntry -Workspace 'WinuX' -Alongside -Windows @(
					(New-TestRecord -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'Live'),
					(New-TestRecord -Handle 99 -ProcessId 9 -ProcessName 'Code' -Title 'Dead')
				))
			)

			$protection = Get-WorkspaceOpenProtection -StatePath $script:TestStatePath

			@($protection.Entries[0].Windows).Count | Should -Be 2
			$protection.WindowHandles.Count | Should -Be 1
			$protection.WindowHandles.Contains([IntPtr]60) | Should -BeTrue
		}

		It "re-resolves a stale handle by process id and name" {
			# Electron applications recreate their window without restarting: new handle, same
			# process. The record's handle is gone but the workspace's window is right there.
			Mock Get-WindowHandle { @((New-TestWindow -Handle 777 -ProcessId 6 -ProcessName 'obsidian' -Title 'Vault - Obsidian')) }
			Write-TestState -Entry @(
				(New-TestEntry -Workspace 'WinuX' -Alongside -Windows @(
					(New-TestRecord -Handle 60 -ProcessId 6 -ProcessName 'obsidian' -Title 'Vault - Obsidian')
				))
			)

			$protection = Get-WorkspaceOpenProtection -StatePath $script:TestStatePath

			$protection.WindowHandles.Contains([IntPtr]777) | Should -BeTrue
		}

		It "re-resolves an outright restart by process name and exact title" {
			# Ladder step 3, sharing Close-Workspace's accepted risk: two workspaces can hold
			# identically titled windows, and a title re-resolution may claim the wrong one.
			Mock Get-WindowHandle { @((New-TestWindow -Handle 888 -ProcessId 999 -ProcessName 'firefox' -Title 'GitHub')) }
			Write-TestState -Entry @(
				(New-TestEntry -Workspace 'WinuX' -Alongside -Windows @(
					(New-TestRecord -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'GitHub')
				))
			)

			$protection = Get-WorkspaceOpenProtection -StatePath $script:TestStatePath

			$protection.WindowHandles.Contains([IntPtr]888) | Should -BeTrue
		}

		It "does not protect the plain session's terminal through a dead alongside terminal record" {
			# Every Windows Terminal window lives in ONE process under a generic title, so a dead
			# alongside terminal record re-resolved by process or title lands on whatever terminal
			# is left - the plain session's own - and the layout then cannot find it.
			Mock Get-WindowHandle {
				@(
					(New-TestWindow -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'Alongside browser'),
					(New-TestWindow -Handle 500 -ProcessId 50 -ProcessName 'WindowsTerminal' -Title 'PowerShell')
				)
			}
			Write-TestState -Entry @(
				(New-TestEntry -Workspace 'WinuX' -Alongside -DesktopOffset 3 -Windows @(
					(New-TestRecord -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'Alongside browser'),
					(New-TestRecord -Handle 400 -ProcessId 50 -ProcessName 'WindowsTerminal' -Title 'PowerShell')
				))
			)

			$protection = Get-WorkspaceOpenProtection -StatePath $script:TestStatePath

			$protection.WindowHandles.Count | Should -Be 1
			$protection.WindowHandles.Contains([IntPtr]60) | Should -BeTrue
			$protection.WindowHandles.Contains([IntPtr]500) | Should -BeFalse
		}

		It "does not re-resolve by process id when the process hosts several windows" {
			# A browser holds many windows in one process; picking the first would protect a window
			# the alongside workspace never owned.
			Mock Get-WindowHandle {
				@(
					(New-TestWindow -Handle 61 -ProcessId 6 -ProcessName 'firefox' -Title 'Plain mail'),
					(New-TestWindow -Handle 62 -ProcessId 6 -ProcessName 'firefox' -Title 'Plain calendar'),
					(New-TestWindow -Handle 70 -ProcessId 7 -ProcessName 'Code' -Title 'Alongside editor')
				)
			}
			Write-TestState -Entry @(
				(New-TestEntry -Workspace 'WinuX' -Alongside -Windows @(
					(New-TestRecord -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'Closed tab'),
					(New-TestRecord -Handle 70 -ProcessId 7 -ProcessName 'Code' -Title 'Alongside editor')
				))
			)

			$protection = Get-WorkspaceOpenProtection -StatePath $script:TestStatePath

			$protection.WindowHandles.Count | Should -Be 1
			$protection.WindowHandles.Contains([IntPtr]70) | Should -BeTrue
		}

		It "preserves every live alongside entry, and only those" {
			Mock Get-WindowHandle {
				@(
					(New-TestWindow -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'B window'),
					(New-TestWindow -Handle 70 -ProcessId 7 -ProcessName 'Code' -Title 'C window'),
					(New-TestWindow -Handle 10 -ProcessId 1 -ProcessName 'chrome' -Title 'Plain window')
				)
			}
			Write-TestState -Entry @(
				(New-TestEntry -Workspace 'Plain' -Windows @(
					(New-TestRecord -Handle 10 -ProcessId 1 -ProcessName 'chrome' -Title 'Plain window')
				)),
				(New-TestEntry -Workspace 'B' -Alongside -DesktopOffset 3 -Windows @(
					(New-TestRecord -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'B window')
				)),
				(New-TestEntry -Workspace 'C' -Alongside -DesktopOffset 5 -Windows @(
					(New-TestRecord -Handle 70 -ProcessId 7 -ProcessName 'Code' -Title 'C window')
				)),
				(New-TestEntry -Workspace 'Dead' -Alongside -DesktopOffset 7 -Windows @(
					(New-TestRecord -Handle 99 -ProcessId 9 -ProcessName 'ghost' -Title 'Gone')
				))
			)

			$protection = Get-WorkspaceOpenProtection -StatePath $script:TestStatePath

			@($protection.Entries.Workspace) | Should -Be @('B', 'C')
			$protection.WindowHandles.Count | Should -Be 2
			$protection.WindowHandles.Contains([IntPtr]10) | Should -BeFalse
		}

		It "reads the default tracker when no -StatePath is given" {
			Mock Get-WindowHandle { @((New-TestWindow -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'Live')) }
			Write-TestState -Entry @(
				(New-TestEntry -Workspace 'WinuX' -Alongside -Windows @(
					(New-TestRecord -Handle 60 -ProcessId 6 -ProcessName 'firefox' -Title 'Live')
				))
			)

			# Get-WorkspaceStatePath is stubbed to the test file, so the default path IS the seam.
			$protection = Get-WorkspaceOpenProtection

			$protection | Should -Not -BeNullOrEmpty
			$protection.Entries[0].Workspace | Should -Be 'WinuX'
		}
	}
}
