#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. (Join-Path $ModuleRoot "Helper\Functions\Get-TerminalTabSnapshot.ps1")

	function Get-WindowHandle { param($ProcessName, $WindowTitle) @() }
	function Get-WindowsTerminalTabTitles { param($WindowHandle) $null }
	function Ensure-DesktopVisible { param($WindowHandle, $DesktopIndex) $null }

	function New-TerminalWindow {
		param($Handle)
		[PSCustomObject]@{ Handle = [IntPtr]$Handle; ProcessName = 'WindowsTerminal'; Title = 'Windows Terminal' }
	}

	# The snapshot is keyed by Int64 (IntPtr.ToInt64), and a hashtable lookup is TYPE-exact: indexing
	# with a bare 407 literal is an Int32 lookup that matches nothing and quietly answers $null. Go
	# through these two so the assertions below use the same key type the real function produces, and
	# so a "not present" assertion cannot pass merely because the types differed.
	function Get-SnapshotTabs {
		param($Snapshot, $Handle)
		$Snapshot[[int64]$Handle]
	}

	function Test-SnapshotHasWindow {
		param($Snapshot, $Handle)
		$Snapshot.ContainsKey([int64]$Handle)
	}
}

Describe "Get-TerminalTabSnapshot" {
	BeforeEach {
		Mock Get-WindowHandle { @() }
		Mock Get-WindowsTerminalTabTitles { $null }
	}

	It "returns nothing when Windows Terminal is not running" {
		$snapshot = Get-TerminalTabSnapshot

		$snapshot.Count | Should -Be 0
	}

	It "keys each window's tab titles by its handle, in tab-strip order" {
		Mock Get-WindowHandle { @((New-TerminalWindow -Handle 407)) }
		Mock Get-WindowsTerminalTabTitles { @('pwsh', 'Server.Api', 'Server.Ui') }

		$snapshot = Get-TerminalTabSnapshot

		$snapshot.Count | Should -Be 1
		Get-SnapshotTabs -Snapshot $snapshot -Handle 407 | Should -Be @('pwsh', 'Server.Api', 'Server.Ui')
	}

	It "keys by Int64, the type a window handle converts to" {
		# Pinned explicitly because getting this wrong is silent: an Int32 lookup against an Int64 key
		# answers $null rather than failing, so a caller diffing two snapshots would see every tab as
		# new instead of seeing an error.
		Mock Get-WindowHandle { @((New-TerminalWindow -Handle 407)) }
		Mock Get-WindowsTerminalTabTitles { @('pwsh') }

		$snapshot = Get-TerminalTabSnapshot

		@($snapshot.Keys)[0] | Should -BeOfType [int64]
	}

	It "captures every terminal window separately" {
		Mock Get-WindowHandle { @((New-TerminalWindow -Handle 407), (New-TerminalWindow -Handle 909)) }
		Mock Get-WindowsTerminalTabTitles {
			param($WindowHandle)
			if ($WindowHandle -eq [IntPtr]407) { @('pwsh') } else { @('Server.Api') }
		}

		$snapshot = Get-TerminalTabSnapshot

		$snapshot.Count | Should -Be 2
		Get-SnapshotTabs -Snapshot $snapshot -Handle 407 | Should -Be @('pwsh')
		Get-SnapshotTabs -Snapshot $snapshot -Handle 909 | Should -Be @('Server.Api')
	}

	It "omits a window whose tabs cannot be read rather than recording it as empty" {
		# Recording an unreadable window as having no tabs would make every one of its tabs look
		# newly created the next time the snapshot is differenced.
		Mock Get-WindowHandle { @((New-TerminalWindow -Handle 407), (New-TerminalWindow -Handle 909)) }
		Mock Get-WindowsTerminalTabTitles {
			param($WindowHandle)
			if ($WindowHandle -eq [IntPtr]407) { @('pwsh') } else { $null }
		}

		$snapshot = Get-TerminalTabSnapshot

		$snapshot.Count | Should -Be 1
		# Both halves asserted: "909 is absent" would hold even for a present key if the lookup used
		# the wrong numeric type, so the readable window is checked as present in the same breath.
		Test-SnapshotHasWindow -Snapshot $snapshot -Handle 407 | Should -BeTrue
		Test-SnapshotHasWindow -Snapshot $snapshot -Handle 909 | Should -BeFalse
	}

	It "ignores windows with no usable handle" {
		Mock Get-WindowHandle { @((New-TerminalWindow -Handle 0)) }
		Mock Get-WindowsTerminalTabTitles { @('pwsh') }

		(Get-TerminalTabSnapshot).Count | Should -Be 0
	}

	It "looks only at Windows Terminal windows" {
		Mock Get-WindowHandle { @() }

		Get-TerminalTabSnapshot | Out-Null

		Should -Invoke Get-WindowHandle -Times 1 -ParameterFilter { $ProcessName -eq 'WindowsTerminal' }
	}

	Context "Terminals on another virtual desktop" {
		BeforeEach {
			$script:desktopVisible = $false
			$script:desktopCalls = @()

			Mock Get-WindowHandle { @((New-TerminalWindow -Handle 407)) }
			# Windows Terminal shows no tab strip at all while its desktop is off screen.
			Mock Get-WindowsTerminalTabTitles {
				if ($script:desktopVisible) { @('pwsh', 'Server.Api') } else { $null }
			}
			Mock Ensure-DesktopVisible {
				param($WindowHandle, $DesktopIndex)
				if ($PSBoundParameters.ContainsKey('DesktopIndex')) {
					$script:desktopCalls += "restore:$DesktopIndex"
					$script:desktopVisible = $false
					return $null
				}
				$script:desktopCalls += "window:$([int64]$WindowHandle)"
				$script:desktopVisible = $true
				return 2
			}
		}

		It "reads nothing from an off-screen terminal by default" {
			(Get-TerminalTabSnapshot).Count | Should -Be 0

			Should -Invoke Ensure-DesktopVisible -Times 0
		}

		It "reads it once asked to make the desktop visible" {
			$snapshot = Get-TerminalTabSnapshot -EnsureVisible

			Get-SnapshotTabs -Snapshot $snapshot -Handle 407 | Should -Be @('pwsh', 'Server.Api')
		}

		It "puts the original desktop back afterwards" {
			Get-TerminalTabSnapshot -EnsureVisible | Out-Null

			$script:desktopCalls | Should -Be @('window:407', 'restore:2')
		}

		It "restores the desktop even when reading throws" {
			Mock Get-WindowsTerminalTabTitles {
				if ($script:desktopVisible) { throw 'UIA exploded' }
				$null
			}

			{ Get-TerminalTabSnapshot -EnsureVisible } | Should -Throw

			$script:desktopCalls | Should -Contain 'restore:2'
		}

		It "does not switch desktops for a terminal that is already readable" {
			$script:desktopVisible = $true

			Get-TerminalTabSnapshot -EnsureVisible | Out-Null

			Should -Invoke Ensure-DesktopVisible -Times 0
		}
	}
}
