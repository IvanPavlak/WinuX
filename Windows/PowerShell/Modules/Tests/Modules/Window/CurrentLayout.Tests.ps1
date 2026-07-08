#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-CurrentLayout.ps1"
	. "$FunctionsPath\Save-CurrentLayout.ps1"

	$script:TestLayoutsDir = Join-Path $env:TEMP ("CurrentLayoutTests_" + $PID)

	function New-TestWindowState {
		param($Handle, $Process, $ProcessId, $Title, $Desktop, $Monitor, $Zone, $Layout, $X, $Y, $W, $H)
		@{
			Handle         = [IntPtr]$Handle
			ProcessName    = $Process
			ProcessId      = [uint32]$ProcessId
			WindowTitle    = $Title
			DesktopNumber  = $Desktop
			Monitor        = $Monitor
			Zone           = $Zone
			Layout         = $Layout
			ExpectedX      = $X
			ExpectedY      = $Y
			ExpectedWidth  = $W
			ExpectedHeight = $H
		}
	}

	$script:TestMonitorConfig = @{
		Primary   = @{ VirtualDesktopLayouts = @{ 1 = 'Two'; 2 = 'One' } }
		Secondary = @{ VirtualDesktopLayouts = @{ 1 = 'Three' } }
	}
}

Describe "CurrentLayout persistence" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Write-LogWarning { }
		Mock Write-LogSuccess { }

		if (Test-Path $script:TestLayoutsDir) { Remove-Item $script:TestLayoutsDir -Recurse -Force }
		New-Item -ItemType Directory -Path $script:TestLayoutsDir -Force | Out-Null
	}

	AfterEach {
		if (Test-Path $script:TestLayoutsDir) { Remove-Item $script:TestLayoutsDir -Recurse -Force }
	}

	Context "Get-CurrentLayout" {
		It "returns null when no snapshot file exists" {
			Get-CurrentLayout -LayoutsDir $script:TestLayoutsDir | Should -BeNullOrEmpty
		}

		It "returns null for a workspace not present in the snapshot" {
			Save-CurrentLayout -Workspace 'Example_PC' -LayoutsDir $script:TestLayoutsDir -MachineType 'PC' `
				-DesktopCount 1 -MonitorConfig $script:TestMonitorConfig -WindowStates @()

			Get-CurrentLayout -LayoutsDir $script:TestLayoutsDir -Workspace 'DoesNotExist' | Should -BeNullOrEmpty
		}
	}

	Context "Save-CurrentLayout round-trip" {
		It "records desktop count, per-monitor FancyZones, and window placement" {
			$windows = @(
				New-TestWindowState -Handle 1180344 -Process 'msedge' -ProcessId 4012 -Title 'Google' -Desktop 1 -Monitor 'Primary' -Zone 'Left' -Layout 'Two' -X 0 -Y 0 -W 1720 -H 1440
				New-TestWindowState -Handle 1245880 -Process 'msedge' -ProcessId 4012 -Title 'Google' -Desktop 1 -Monitor 'Primary' -Zone 'Right' -Layout 'Two' -X 1720 -Y 0 -W 1720 -H 1440
			)

			Save-CurrentLayout -Workspace 'Example_PC' -LayoutsDir $script:TestLayoutsDir -MachineType 'PC' `
				-DesktopCount 2 -MonitorConfig $script:TestMonitorConfig -WindowStates $windows

			$section = Get-CurrentLayout -LayoutsDir $script:TestLayoutsDir -Workspace 'Example_PC'

			$section | Should -Not -BeNullOrEmpty
			$section.DesktopCount | Should -Be 2
			$section.Windows.Count | Should -Be 2

			# FancyZones recorded per monitor per desktop
			$desktop1 = $section.Desktops | Where-Object { $_.DesktopNumber -eq 1 }
			$desktop1.Monitors.Primary | Should -Be 'Two'
			$desktop1.Monitors.Secondary | Should -Be 'Three'
			$desktop2 = $section.Desktops | Where-Object { $_.DesktopNumber -eq 2 }
			$desktop2.Monitors.Primary | Should -Be 'One'

			# Window records preserve handle, process fingerprint and zone placement
			$left = $section.Windows | Where-Object { $_.Zone -eq 'Left' }
			$left.Handle | Should -Be 1180344
			$left.ProcessName | Should -Be 'msedge'
			$left.Monitor | Should -Be 'Primary'
			$left.Desktop | Should -Be 1

			$right = $section.Windows | Where-Object { $_.Zone -eq 'Right' }
			$right.Handle | Should -Be 1245880
		}

		It "stores desktop numbers layout-relative by stripping the desktop offset" {
			# Tracking stores the display desktop (with offset); the snapshot must store it
			# offset-independent so it is reusable on a later normal-mode reopen.
			$windows = @(
				New-TestWindowState -Handle 50 -Process 'msedge' -ProcessId 1 -Title 'X' -Desktop 3 -Monitor 'Primary' -Zone 'Left' -Layout 'Two' -X 0 -Y 0 -W 100 -H 100
			)

			Save-CurrentLayout -Workspace 'Server_PC' -LayoutsDir $script:TestLayoutsDir -MachineType 'PC' `
				-DesktopOffset 2 -Alongside -DesktopCount 1 -MonitorConfig $script:TestMonitorConfig -WindowStates $windows

			$section = Get-CurrentLayout -LayoutsDir $script:TestLayoutsDir -Workspace 'Server_PC'
			$section.Alongside | Should -BeTrue
			$section.DesktopOffset | Should -Be 2
			# Display desktop 3 minus offset 2 => layout-relative desktop 1
			$section.Windows[0].Desktop | Should -Be 1
		}
	}

	Context "Reflect all open workspaces" {
		It "replaces other workspaces on a normal (non-alongside) save" {
			Save-CurrentLayout -Workspace 'WinuX_PC' -LayoutsDir $script:TestLayoutsDir -MachineType 'PC' `
				-DesktopCount 1 -MonitorConfig $script:TestMonitorConfig -WindowStates @()

			Save-CurrentLayout -Workspace 'Server_PC' -LayoutsDir $script:TestLayoutsDir -MachineType 'PC' `
				-DesktopCount 1 -MonitorConfig $script:TestMonitorConfig -WindowStates @()

			$snapshot = Get-CurrentLayout -LayoutsDir $script:TestLayoutsDir
			$snapshot.Workspaces.Contains('Server_PC') | Should -BeTrue
			$snapshot.Workspaces.Contains('WinuX_PC') | Should -BeFalse
		}

		It "preserves existing workspaces on an alongside save" {
			Save-CurrentLayout -Workspace 'WinuX_PC' -LayoutsDir $script:TestLayoutsDir -MachineType 'PC' `
				-DesktopCount 1 -MonitorConfig $script:TestMonitorConfig -WindowStates @()

			Save-CurrentLayout -Workspace 'Server_PC' -LayoutsDir $script:TestLayoutsDir -MachineType 'PC' `
				-Alongside -DesktopOffset 1 -DesktopCount 1 -MonitorConfig $script:TestMonitorConfig -WindowStates @()

			$snapshot = Get-CurrentLayout -LayoutsDir $script:TestLayoutsDir
			$snapshot.Workspaces.Contains('Server_PC') | Should -BeTrue
			$snapshot.Workspaces.Contains('WinuX_PC') | Should -BeTrue
		}
	}
}
