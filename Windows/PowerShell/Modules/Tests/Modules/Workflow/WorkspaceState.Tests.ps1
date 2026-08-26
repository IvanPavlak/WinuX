#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Format-WorkspaceStateContent.ps1"
	. "$FunctionsPath\Get-WorkspaceState.ps1"
	. "$FunctionsPath\Save-WorkspaceState.ps1"

	$script:TestStateDir = Join-Path $env:TEMP ("WorkspaceStateTests_" + $PID)
	$script:TestStatePath = Join-Path $script:TestStateDir "OpenWorkspaces.txt"

	# Save-WorkspaceState delegates the before/after diff to Get-WorkspaceOpenDelta; these tests
	# cover persistence and merge semantics, so the delta is stubbed and asserted separately in
	# Get-WorkspaceOpenDelta.Tests.ps1.
	function Get-WorkspaceOpenDelta {
		param($Workspace, $ExistingWindowHandles, $ExistingTerminalTabs, $DesktopOffset, [switch]$Alongside, $ProtectedWindowHandles)
	}

	function Get-WorkspaceStatePath { $script:TestStatePath }

	function New-TestEntry {
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
}

Describe "Workspace state persistence" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Write-LogWarning { }

		Mock Get-WorkspaceOpenDelta {
			param($Workspace, $ExistingWindowHandles, $ExistingTerminalTabs, $DesktopOffset, [switch]$Alongside, $ProtectedWindowHandles)
			New-TestEntry -Workspace $Workspace -Alongside:$Alongside -DesktopOffset $DesktopOffset -Windows @(
				[ordered]@{ Handle = 101; ProcessId = 11; ProcessName = 'firefox'; Title = "$Workspace tab" }
			)
		}

		if (Test-Path $script:TestStateDir) { Remove-Item $script:TestStateDir -Recurse -Force }
		New-Item -ItemType Directory -Path $script:TestStateDir -Force | Out-Null
	}

	AfterEach {
		if (Test-Path $script:TestStateDir) { Remove-Item $script:TestStateDir -Recurse -Force }
	}

	Context "Get-WorkspaceState" {
		It "returns null when no tracker file exists" {
			Get-WorkspaceState -StatePath $script:TestStatePath | Should -BeNullOrEmpty
		}

		It "returns null when the tracker file cannot be parsed" {
			Set-Content -LiteralPath $script:TestStatePath -Value "this is not a data file {{{" -Encoding UTF8

			Get-WorkspaceState -StatePath $script:TestStatePath | Should -BeNullOrEmpty
		}

		It "distinguishes an empty tracker from a missing one" {
			Save-WorkspaceState -Entry @() -StatePath $script:TestStatePath

			$state = Get-WorkspaceState -StatePath $script:TestStatePath

			$state | Should -Not -BeNullOrEmpty
			@($state.Entries).Count | Should -Be 0
		}

		It "filters to the requested workspace regardless of case" {
			Save-WorkspaceState -Entry @(
				(New-TestEntry -Workspace 'Server'),
				(New-TestEntry -Workspace 'WinuX')
			) -StatePath $script:TestStatePath

			$filtered = Get-WorkspaceState -StatePath $script:TestStatePath -Workspace 'server'

			@($filtered.Entries).Count | Should -Be 1
			$filtered.Entries[0].Workspace | Should -Be 'Server'
		}

		It "returns no entries for a workspace the tracker does not hold" {
			Save-WorkspaceState -Entry @((New-TestEntry -Workspace 'Server')) -StatePath $script:TestStatePath

			@((Get-WorkspaceState -StatePath $script:TestStatePath -Workspace 'Absent').Entries).Count | Should -Be 0
		}
	}

	Context "Save-WorkspaceState round-trip" {
		It "preserves window and tab records through a write and read" {
			$entry = New-TestEntry -Workspace 'Server' -DesktopOffset 3 -Windows @(
				[ordered]@{ Handle = 4242; ProcessId = 99; ProcessName = 'firefox'; Title = "Ivan's page" }
			) -TerminalTabs @(
				[ordered]@{ WindowHandle = 777; Title = 'Server.Api' }
			)

			Save-WorkspaceState -Entry @($entry) -StatePath $script:TestStatePath
			$read = (Get-WorkspaceState -StatePath $script:TestStatePath).Entries[0]

			$read.Workspace | Should -Be 'Server'
			$read.DesktopOffset | Should -Be 3
			$read.Windows[0].Handle | Should -Be 4242
			$read.Windows[0].ProcessName | Should -Be 'firefox'
			# Single quotes inside a title would end the literal early if they were not doubled.
			$read.Windows[0].Title | Should -Be "Ivan's page"
			$read.TerminalTabs[0].WindowHandle | Should -Be 777
			$read.TerminalTabs[0].Title | Should -Be 'Server.Api'
		}

		It "creates the state directory when it does not exist yet" {
			Remove-Item $script:TestStateDir -Recurse -Force

			Save-WorkspaceState -Entry @((New-TestEntry -Workspace 'Server')) -StatePath $script:TestStatePath

			Test-Path $script:TestStatePath | Should -BeTrue
		}

		It "clears the tracker when handed no entries" {
			Save-WorkspaceState -Entry @((New-TestEntry -Workspace 'Server')) -StatePath $script:TestStatePath
			Save-WorkspaceState -Entry @() -StatePath $script:TestStatePath

			@((Get-WorkspaceState -StatePath $script:TestStatePath).Entries).Count | Should -Be 0
		}

		It "warns instead of throwing when the tracker cannot be written" {
			$unwritable = Join-Path $script:TestStateDir "OpenWorkspaces.txt\nested.txt"
			Set-Content -LiteralPath $script:TestStatePath -Value "placeholder" -Encoding UTF8

			{ Save-WorkspaceState -Entry @() -StatePath $unwritable } | Should -Not -Throw

			Should -Invoke Write-LogWarning -Times 1
		}
	}

	Context "Merge semantics" {
		It "replaces the tracker on a plain open, because that open reset the desktops" {
			Save-WorkspaceState -Entry @((New-TestEntry -Workspace 'Stale')) -StatePath $script:TestStatePath

			Save-WorkspaceState -Workspace 'Server' -StatePath $script:TestStatePath

			$entries = @((Get-WorkspaceState -StatePath $script:TestStatePath).Entries)
			$entries.Count | Should -Be 1
			$entries[0].Workspace | Should -Be 'Server'
		}

		It "appends on an alongside open, keeping the workspaces already on screen" {
			Save-WorkspaceState -Workspace 'Server' -StatePath $script:TestStatePath
			Save-WorkspaceState -Workspace 'WinuX' -Alongside -DesktopOffset 3 -StatePath $script:TestStatePath

			$entries = @((Get-WorkspaceState -StatePath $script:TestStatePath).Entries)

			$entries.Count | Should -Be 2
			$entries[0].Workspace | Should -Be 'Server'
			$entries[1].Workspace | Should -Be 'WinuX'
			$entries[1].Alongside | Should -BeTrue
			$entries[1].DesktopOffset | Should -Be 3
		}

		It "records a second entry for a name already tracked, because it is a separate instance" {
			Save-WorkspaceState -Workspace 'Server' -StatePath $script:TestStatePath
			Save-WorkspaceState -Workspace 'Server' -Alongside -DesktopOffset 3 -StatePath $script:TestStatePath

			$entries = @((Get-WorkspaceState -StatePath $script:TestStatePath).Entries)

			$entries.Count | Should -Be 2
			@($entries | Where-Object { $_.Workspace -eq 'Server' }).Count | Should -Be 2
			$entries[0].Alongside | Should -BeFalse
			$entries[1].Alongside | Should -BeTrue
		}

		It "seeds a plain save with the preserved alongside entries, ahead of the new record" {
			# A plain protecting open replaces the file - without the seed the preserved
			# workspaces' entries would be wiped and Close-Workspace could never close them.
			$preserved = New-TestEntry -Workspace 'Alongside' -Alongside -DesktopOffset 5

			Save-WorkspaceState -Workspace 'Server' -PreserveEntry @($preserved) -StatePath $script:TestStatePath

			$entries = @((Get-WorkspaceState -StatePath $script:TestStatePath).Entries)
			$entries.Count | Should -Be 2
			$entries[0].Workspace | Should -Be 'Alongside'
			$entries[0].Alongside | Should -BeTrue
			$entries[1].Workspace | Should -Be 'Server'
		}

		It "does not double-seed an appending save, whose file already holds the preserved entries" {
			# The second workspace of a plain "Open-Workspace a, b" run appends - the file was
			# just written by the first workspace's seeded save, so seeding again would duplicate
			# every preserved entry.
			$preserved = New-TestEntry -Workspace 'Alongside' -Alongside -DesktopOffset 5

			Save-WorkspaceState -Workspace 'First' -PreserveEntry @($preserved) -StatePath $script:TestStatePath
			Save-WorkspaceState -Workspace 'Second' -Append -PreserveEntry @($preserved) -StatePath $script:TestStatePath

			$entries = @((Get-WorkspaceState -StatePath $script:TestStatePath).Entries)
			$entries.Count | Should -Be 3
			@($entries | Where-Object { $_.Workspace -eq 'Alongside' }).Count | Should -Be 1
		}

		It "forwards the protected handles to the delta so adoption cannot claim them" {
			$protected = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$protected.Add([IntPtr]9)

			Save-WorkspaceState -Workspace 'Server' -ProtectedWindowHandles $protected -StatePath $script:TestStatePath

			Should -Invoke Get-WorkspaceOpenDelta -Times 1 -ParameterFilter {
				$ProtectedWindowHandles -and $ProtectedWindowHandles.Contains([IntPtr]9)
			}
		}

		It "forwards the pre-open captures to the delta rather than diffing them itself" {
			$handles = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$handles.Add([IntPtr]5)
			$tabs = @{ 777 = @('pwsh') }

			Save-WorkspaceState -Workspace 'Server' -ExistingWindowHandles $handles -ExistingTerminalTabs $tabs `
				-DesktopOffset 2 -Alongside -StatePath $script:TestStatePath

			Should -Invoke Get-WorkspaceOpenDelta -Times 1 -ParameterFilter {
				$Workspace -eq 'Server' -and
				$DesktopOffset -eq 2 -and
				$Alongside -and
				$ExistingWindowHandles.Contains([IntPtr]5) -and
				$ExistingTerminalTabs[777] -contains 'pwsh'
			}
		}
	}
}
