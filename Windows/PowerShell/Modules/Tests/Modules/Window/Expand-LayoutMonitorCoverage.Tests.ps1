#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force

	. (Join-Path $PSScriptRoot "MonitorFixtures.ps1")

	# A layout as Import-PowerShellDataFile would return it: Monitors keyed by label, each with
	# 1-based VirtualDesktopLayouts. Built fresh per test because the function mutates in place.
	function New-LayoutConfig {
		param (
			[string[]]$MonitorLabels = @('Primary', 'Secondary'),
			[hashtable]$ExtraKeys = @{}
		)

		$monitors = @{}
		foreach ($label in $MonitorLabels) {
			$monitors[$label] = @{
				VirtualDesktopLayouts = @{
					1 = "Layout-$label-1"
					2 = "Layout-$label-2"
				}
			}
		}

		$config = @{
			Monitors = $monitors
			Layout   = @(
				@{ ProcessName = "wt"; Monitor = "Primary"; DesktopNumber = 1; Zone = "Left" }
			)
		}

		foreach ($key in $ExtraKeys.Keys) {
			$config[$key] = $ExtraKeys[$key]
		}

		return $config
	}
}

Describe "Expand-LayoutMonitorCoverage" {
	Context "extending to undefined monitors" {
		It "adds an attached monitor the layout file does not define" {
			$config = New-LayoutConfig -MonitorLabels @('Primary', 'Secondary')

			$added = @(Expand-LayoutMonitorCoverage -Config $config -MonitorInfo (New-MonitorFixture -Count 3))

			$added | Should -Be @('Monitor3')
			$config.Monitors.ContainsKey('Monitor3') | Should -Be $true
		}

		It "clones the template monitor's per-desktop layouts onto the added monitor" {
			$config = New-LayoutConfig -MonitorLabels @('Primary', 'Secondary')

			$null = Expand-LayoutMonitorCoverage -Config $config -MonitorInfo (New-MonitorFixture -Count 3)

			$config.Monitors.Monitor3.VirtualDesktopLayouts[1] | Should -Be 'Layout-Primary-1'
			$config.Monitors.Monitor3.VirtualDesktopLayouts[2] | Should -Be 'Layout-Primary-2'
		}

		It "adds every missing monitor at once" {
			$config = New-LayoutConfig -MonitorLabels @('Primary')

			$added = @(Expand-LayoutMonitorCoverage -Config $config -MonitorInfo (New-MonitorFixture -Count 3))

			$added | Should -Be @('Secondary', 'Monitor3')
		}

		It "picks the template in label order rather than hashtable order" {
			# Primary is the template whenever the file defines it, regardless of the order
			# Import-PowerShellDataFile happens to enumerate the Monitors keys in.
			$config = New-LayoutConfig -MonitorLabels @('Secondary', 'Primary')

			$null = Expand-LayoutMonitorCoverage -Config $config -MonitorInfo (New-MonitorFixture -Count 3)

			$config.Monitors.Monitor3.VirtualDesktopLayouts[1] | Should -Be 'Layout-Primary-1'
		}

		It "falls back to the first defined label when Primary is absent" {
			$config = New-LayoutConfig -MonitorLabels @('Secondary')

			$added = @(Expand-LayoutMonitorCoverage -Config $config -MonitorInfo (New-MonitorFixture -Count 3))

			$added | Should -Be @('Primary', 'Monitor3')
			$config.Monitors.Primary.VirtualDesktopLayouts[1] | Should -Be 'Layout-Secondary-1'
		}

		It "never touches a monitor the layout already defines" {
			$config = New-LayoutConfig -MonitorLabels @('Primary', 'Secondary')

			$null = Expand-LayoutMonitorCoverage -Config $config -MonitorInfo (New-MonitorFixture -Count 3)

			$config.Monitors.Secondary.VirtualDesktopLayouts[1] | Should -Be 'Layout-Secondary-1'
		}

		It "leaves the Layout array alone so nothing is moved onto the added monitor" {
			$config = New-LayoutConfig -MonitorLabels @('Primary', 'Secondary')

			$null = Expand-LayoutMonitorCoverage -Config $config -MonitorInfo (New-MonitorFixture -Count 3)

			@($config.Layout).Count | Should -Be 1
			@($config.Layout | Where-Object { $_.Monitor -eq 'Monitor3' }).Count | Should -Be 0
		}
	}

	Context "nothing to do" {
		It "adds nothing when the layout already covers every attached monitor" {
			$config = New-LayoutConfig -MonitorLabels @('Primary', 'Secondary')

			$added = @(Expand-LayoutMonitorCoverage -Config $config -MonitorInfo (New-MonitorFixture -Count 2))

			$added.Count | Should -Be 0
			@($config.Monitors.Keys).Count | Should -Be 2
		}

		It "adds nothing when the layout defines more monitors than are attached" {
			$config = New-LayoutConfig -MonitorLabels @('Primary', 'Secondary', 'Monitor3')

			$added = @(Expand-LayoutMonitorCoverage -Config $config -MonitorInfo (New-MonitorFixture -Count 2))

			$added.Count | Should -Be 0
			$config.Monitors.ContainsKey('Monitor3') | Should -Be $true
		}

		It "adds nothing when the config has no Monitors section" {
			$config = @{ Layout = @() }

			$added = @(Expand-LayoutMonitorCoverage -Config $config -MonitorInfo (New-MonitorFixture -Count 3))

			$added.Count | Should -Be 0
		}

		It "adds nothing when the template monitor has no VirtualDesktopLayouts to clone" {
			$config = @{ Monitors = @{ Primary = @{ Layout = "One" } } }

			$added = @(Expand-LayoutMonitorCoverage -Config $config -MonitorInfo (New-MonitorFixture -Count 3))

			$added.Count | Should -Be 0
			$config.Monitors.ContainsKey('Monitor3') | Should -Be $false
		}

		It "does not throw on a null config" {
			{ Expand-LayoutMonitorCoverage -Config $null -MonitorInfo (New-MonitorFixture -Count 3) } | Should -Not -Throw
		}

		It "adds nothing when no monitors can be detected" {
			$config = New-LayoutConfig -MonitorLabels @('Primary')
			Mock Get-MonitorInfo { @() } -ModuleName Window

			$added = @(Expand-LayoutMonitorCoverage -Config $config)

			$added.Count | Should -Be 0
		}
	}

	Context "AutoExtendMonitors opt-out" {
		It "adds nothing when AutoExtendMonitors is false" {
			$config = New-LayoutConfig -MonitorLabels @('Primary') -ExtraKeys @{ AutoExtendMonitors = $false }

			$added = @(Expand-LayoutMonitorCoverage -Config $config -MonitorInfo (New-MonitorFixture -Count 3))

			$added.Count | Should -Be 0
			$config.Monitors.ContainsKey('Monitor3') | Should -Be $false
		}

		It "extends when AutoExtendMonitors is explicitly true" {
			$config = New-LayoutConfig -MonitorLabels @('Primary', 'Secondary') -ExtraKeys @{ AutoExtendMonitors = $true }

			$added = @(Expand-LayoutMonitorCoverage -Config $config -MonitorInfo (New-MonitorFixture -Count 3))

			$added | Should -Be @('Monitor3')
		}

		It "extends when the key is absent, since extending is the default" {
			$config = New-LayoutConfig -MonitorLabels @('Primary', 'Secondary')

			$config.ContainsKey('AutoExtendMonitors') | Should -Be $false
			@(Expand-LayoutMonitorCoverage -Config $config -MonitorInfo (New-MonitorFixture -Count 3)) | Should -Be @('Monitor3')
		}
	}

	Context "idempotency" {
		It "adds nothing on a second pass over the same config" {
			$config = New-LayoutConfig -MonitorLabels @('Primary', 'Secondary')
			$monitors = New-MonitorFixture -Count 3

			$first = @(Expand-LayoutMonitorCoverage -Config $config -MonitorInfo $monitors)
			$second = @(Expand-LayoutMonitorCoverage -Config $config -MonitorInfo $monitors)

			$first | Should -Be @('Monitor3')
			$second.Count | Should -Be 0
		}
	}
}
