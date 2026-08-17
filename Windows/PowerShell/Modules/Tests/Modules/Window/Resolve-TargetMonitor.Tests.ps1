#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	# Get-MonitorSpecs is used for real rather than mocked: label resolution is now the thing
	# under test (labels follow physical position, not enumeration order), so a stubbed spec
	# table would assert against the stub instead of the real mapping.
	. "$FunctionsPath\Resolve-MonitorLabel.ps1"
	. "$FunctionsPath\Get-MonitorSpecs.ps1"
	. "$FunctionsPath\Resolve-TargetMonitor.ps1"

	. (Join-Path $PSScriptRoot "MonitorFixtures.ps1")
}

Describe "Resolve-TargetMonitor" {
	BeforeEach {
		# Primary on the left, secondary on the right; both 1920x1080 with a 40px
		# taskbar reserved at the bottom of the work area.
		$script:primary = [PSCustomObject]@{
			DeviceName = '\\.\DISPLAY1'
			Left = 0; Top = 0; Right = 1920; Bottom = 1080
			Width = 1920; Height = 1080
			WorkAreaLeft = 0; WorkAreaTop = 0; WorkAreaWidth = 1920; WorkAreaHeight = 1040
			IsPrimary = $true
		}
		$script:secondary = [PSCustomObject]@{
			DeviceName = '\\.\DISPLAY2'
			Left = 1920; Top = 0; Right = 3840; Bottom = 1080
			Width = 1920; Height = 1080
			WorkAreaLeft = 1920; WorkAreaTop = 0; WorkAreaWidth = 1920; WorkAreaHeight = 1040
			IsPrimary = $false
		}
		$script:monitors = @($script:primary, $script:secondary)

		Mock Get-MonitorInfo { $script:monitors }
	}

	Context "no targeting requested" {
		It "reports Requested false for an empty specifier" {
			$result = Resolve-TargetMonitor -Monitor "" -MonitorInfo $script:monitors

			$result.Requested | Should -BeFalse
			$result.Monitor | Should -BeNullOrEmpty
			$result.ErrorMessage | Should -BeNullOrEmpty
		}

		It "reports Requested false for whitespace and never enumerates monitors" {
			$result = Resolve-TargetMonitor -Monitor "   "

			$result.Requested | Should -BeFalse
			Should -Invoke Get-MonitorInfo -Times 0
		}
	}

	Context "resolution by index" {
		It "resolves a 1-based index against enumeration order" {
			$result = Resolve-TargetMonitor -Monitor "2" -MonitorInfo $script:monitors

			$result.Monitor.DeviceName | Should -Be '\\.\DISPLAY2'
			# The Label is the resolved monitor's STANDARDIZED label, not a restatement of the
			# index: "Monitor2" would have named a slot that no layout file can target, and on a
			# three-monitor setup "-Monitor 3" would log "Monitor3" while pointing at a different
			# panel than the label "Monitor3" refers to.
			$result.Label | Should -Be 'Secondary'
			$result.ErrorMessage | Should -BeNullOrEmpty
		}

		It "returns an error message for an out-of-range index without throwing" {
			$result = Resolve-TargetMonitor -Monitor "5" -MonitorInfo $script:monitors

			$result.Monitor | Should -BeNullOrEmpty
			$result.Requested | Should -BeTrue
			$result.ErrorMessage | Should -Match 'out of range'
		}
	}

	Context "resolution by label and device name" {
		It "resolves Primary to whichever monitor is currently primary" {
			$result = Resolve-TargetMonitor -Monitor "Primary" -MonitorInfo $script:monitors

			$result.Monitor.DeviceName | Should -Be '\\.\DISPLAY1'
			$result.Label | Should -Be 'Primary'
		}

		It "resolves a standardized label through Get-MonitorSpecs geometry" {
			$result = Resolve-TargetMonitor -Monitor "Secondary" -MonitorInfo $script:monitors

			$result.Monitor.DeviceName | Should -Be '\\.\DISPLAY2'
			$result.Label | Should -Be 'Secondary'
		}

		It "resolves an exact device name case-insensitively" {
			$result = Resolve-TargetMonitor -Monitor '\\.\display2' -MonitorInfo $script:monitors

			$result.Monitor.DeviceName | Should -Be '\\.\DISPLAY2'
			# Reported as the standardized label, so a device-name target logs the same name a
			# layout file would use for that panel.
			$result.Label | Should -Be 'Secondary'
		}

		It "falls back to the device name when no standardized label matches" {
			Mock Get-MonitorSpecs { [PSCustomObject]@{} }

			$result = Resolve-TargetMonitor -Monitor '\\.\DISPLAY2' -MonitorInfo $script:monitors

			$result.Monitor.DeviceName | Should -Be '\\.\DISPLAY2'
			$result.Label | Should -Be '\\.\DISPLAY2'
		}

		It "returns an error message listing available labels when unresolved" {
			$result = Resolve-TargetMonitor -Monitor "Monitor7" -MonitorInfo $script:monitors

			$result.Monitor | Should -BeNullOrEmpty
			$result.ErrorMessage | Should -Match 'Could not resolve monitor'
			$result.ErrorMessage | Should -Match 'Secondary'
		}

		It "lists Primary and Secondary but no MonitorN for a two-monitor setup" {
			$result = Resolve-TargetMonitor -Monitor "Nope" -MonitorInfo $script:monitors

			$result.ErrorMessage | Should -Match 'Primary, Secondary'
			$result.ErrorMessage | Should -Not -Match 'Monitor3'
		}
	}

	Context "three monitors" {
		BeforeEach {
			# The fixture enumerates in a deliberately scrambled order, so labels can only come
			# out right if they are derived from the physical arrangement.
			$script:threeMonitors = New-MonitorFixture -Count 3
			Mock Get-MonitorInfo { $script:threeMonitors }
		}

		It "resolves Monitor3 to the rightmost display, not the third enumerated one" {
			$result = Resolve-TargetMonitor -Monitor "Monitor3" -MonitorInfo $script:threeMonitors

			$result.Monitor.DeviceName | Should -Be (Get-ExpectedMonitorLabel 'Monitor3')
			$result.Label | Should -Be 'Monitor3'
		}

		It "resolves Secondary to the leftmost non-primary display" {
			$result = Resolve-TargetMonitor -Monitor "Secondary" -MonitorInfo $script:threeMonitors

			$result.Monitor.DeviceName | Should -Be (Get-ExpectedMonitorLabel 'Secondary')
			$result.Label | Should -Be 'Secondary'
		}

		It "reports the standardized label of whichever display an index lands on" {
			# Index 1 is the FIRST ENUMERATED monitor, which in this fixture is the rightmost
			# panel - the one labeled Monitor3. The Label has to say so.
			$result = Resolve-TargetMonitor -Monitor "1" -MonitorInfo $script:threeMonitors

			$result.Monitor.DeviceName | Should -Be $script:threeMonitors[0].DeviceName
			$result.Label | Should -Be 'Monitor3'
		}

		It "lists all three labels when a monitor cannot be resolved" {
			$result = Resolve-TargetMonitor -Monitor "Monitor9" -MonitorInfo $script:threeMonitors

			$result.ErrorMessage | Should -Match 'Primary, Secondary, Monitor3'
		}

		It "reports an out-of-range index against the real monitor count" {
			$result = Resolve-TargetMonitor -Monitor "4" -MonitorInfo $script:threeMonitors

			$result.Monitor | Should -BeNullOrEmpty
			$result.ErrorMessage | Should -Match '1\.\.3'
		}
	}

	Context "monitor enumeration" {
		It "enumerates monitors itself when MonitorInfo is omitted" {
			$result = Resolve-TargetMonitor -Monitor "1"

			Should -Invoke Get-MonitorInfo -Times 1
			$result.Monitor.DeviceName | Should -Be '\\.\DISPLAY1'
		}

		It "reports an error when no monitors can be detected" {
			Mock Get-MonitorInfo { @() }

			$result = Resolve-TargetMonitor -Monitor "1"

			$result.Monitor | Should -BeNullOrEmpty
			$result.ErrorMessage | Should -Match 'Could not detect any monitors'
		}
	}
}
