#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Resolve-TargetMonitor.ps1"
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
		Mock Get-MonitorSpecs {
			[PSCustomObject]@{
				Primary   = [PSCustomObject]@{ X = 0; Y = 0; Width = 1920; Height = 1080 }
				Secondary = [PSCustomObject]@{ X = 1920; Y = 0; Width = 1920; Height = 1080 }
			}
		}
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
			$result.Label | Should -Be 'Monitor2'
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
			$result.Label | Should -Be '\\.\DISPLAY2'
		}

		It "returns an error message listing available labels when unresolved" {
			$result = Resolve-TargetMonitor -Monitor "Monitor7" -MonitorInfo $script:monitors

			$result.Monitor | Should -BeNullOrEmpty
			$result.ErrorMessage | Should -Match 'Could not resolve monitor'
			$result.ErrorMessage | Should -Match 'Secondary'
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
