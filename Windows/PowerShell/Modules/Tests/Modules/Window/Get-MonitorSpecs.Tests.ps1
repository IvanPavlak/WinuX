#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force

	. (Join-Path $PSScriptRoot "MonitorFixtures.ps1")
}

Describe "Get-MonitorSpecs" {
	Context "Monitor Specification Formatting" {
		It "Should return hashtable when AsHashtable switch is used" {
			# Mock Get-MonitorInfo by using pre-defined monitor data
			$mockMonitors = @(
				[PSCustomObject]@{
					DeviceName = "\\.\DISPLAY1"
					Left       = 0
					Top        = 0
					Width      = 1920
					Height     = 1080
					IsPrimary  = $true
				}
			)

			$result = Get-MonitorSpecs -MonitorInfo $mockMonitors -AsHashtable

			$result | Should -BeOfType [hashtable]
			$result.Primary | Should -Not -BeNullOrEmpty
			$result.Primary.X | Should -Be 0
			$result.Primary.Y | Should -Be 0
			$result.Primary.Width | Should -Be 1920
			$result.Primary.Height | Should -Be 1080
		}

		It "Should label primary monitor correctly" {
			$mockMonitors = @(
				[PSCustomObject]@{
					DeviceName = "\\.\DISPLAY1"
					Left       = 0
					Top        = 0
					Width      = 1920
					Height     = 1080
					IsPrimary  = $true
				}
			)

			$result = Get-MonitorSpecs -MonitorInfo $mockMonitors -AsHashtable

			$result.ContainsKey("Primary") | Should -Be $true
		}

		It "Should label secondary monitors correctly" {
			$mockMonitors = @(
				[PSCustomObject]@{
					DeviceName = "\\.\DISPLAY1"
					Left       = 0
					Top        = 0
					Width      = 1920
					Height     = 1080
					IsPrimary  = $true
				}
				[PSCustomObject]@{
					DeviceName = "\\.\DISPLAY2"
					Left       = 1920
					Top        = 0
					Width      = 1920
					Height     = 1080
					IsPrimary  = $false
				}
			)

			$result = Get-MonitorSpecs -MonitorInfo $mockMonitors -AsHashtable

			$result.ContainsKey("Primary") | Should -Be $true
			$result.ContainsKey("Secondary") | Should -Be $true
			$result.Secondary.X | Should -Be 1920
		}

		It "Should handle three or more monitors with proper labeling" {
			$mockMonitors = @(
				[PSCustomObject]@{
					DeviceName = "\\.\DISPLAY1"
					Left       = 0
					Top        = 0
					Width      = 1920
					Height     = 1080
					IsPrimary  = $true
				}
				[PSCustomObject]@{
					DeviceName = "\\.\DISPLAY2"
					Left       = 1920
					Top        = 0
					Width      = 1920
					Height     = 1080
					IsPrimary  = $false
				}
				[PSCustomObject]@{
					DeviceName = "\\.\DISPLAY3"
					Left       = 3840
					Top        = 0
					Width      = 1920
					Height     = 1080
					IsPrimary  = $false
				}
			)

			$result = Get-MonitorSpecs -MonitorInfo $mockMonitors -AsHashtable

			$result.ContainsKey("Primary") | Should -Be $true
			$result.ContainsKey("Secondary") | Should -Be $true
			$result.ContainsKey("Monitor3") | Should -Be $true
		}

		It "Should include device name in specifications" {
			$mockMonitors = @(
				[PSCustomObject]@{
					DeviceName = "\\.\DISPLAY1"
					Left       = 0
					Top        = 0
					Width      = 1920
					Height     = 1080
					IsPrimary  = $true
				}
			)

			$result = Get-MonitorSpecs -MonitorInfo $mockMonitors -AsHashtable

			$result.Primary.DeviceName | Should -Be "\\.\DISPLAY1"
		}
	}

	Context "Work Area Geometry" {
		It "Should expose work-area fields distinct from bounds when a taskbar shrinks the work area" {
			# FancyZones lays zones over the WORK AREA - zone math consumes these fields.
			$mockMonitors = @(
				[PSCustomObject]@{
					DeviceName     = "\\.\DISPLAY1"
					Left           = 0
					Top            = 0
					Width          = 1920
					Height         = 1080
					WorkAreaLeft   = 0
					WorkAreaTop    = 0
					WorkAreaWidth  = 1920
					WorkAreaHeight = 1032   # 48px visible taskbar
					IsPrimary      = $true
				}
			)

			$result = Get-MonitorSpecs -MonitorInfo $mockMonitors -AsHashtable

			$result.Primary.Width | Should -Be 1920
			$result.Primary.Height | Should -Be 1080
			$result.Primary.WorkX | Should -Be 0
			$result.Primary.WorkY | Should -Be 0
			$result.Primary.WorkWidth | Should -Be 1920
			$result.Primary.WorkHeight | Should -Be 1032
		}

		It "Should fall back to bounds for work-area fields when the input carries none" {
			# Older callers / fixtures without WorkArea* data degrade to bounds-based geometry.
			$mockMonitors = @(
				[PSCustomObject]@{
					DeviceName = "\\.\DISPLAY1"
					Left       = 100
					Top        = -1440
					Width      = 3440
					Height     = 1440
					IsPrimary  = $true
				}
			)

			$result = Get-MonitorSpecs -MonitorInfo $mockMonitors -AsHashtable

			$result.Primary.WorkX | Should -Be 100
			$result.Primary.WorkY | Should -Be -1440
			$result.Primary.WorkWidth | Should -Be 3440
			$result.Primary.WorkHeight | Should -Be 1440
		}

		It "Should expose work-area fields for secondary monitors too" {
			$mockMonitors = @(
				[PSCustomObject]@{
					DeviceName = "\\.\DISPLAY1"; Left = 0; Top = 0; Width = 1920; Height = 1080
					WorkAreaLeft = 0; WorkAreaTop = 0; WorkAreaWidth = 1920; WorkAreaHeight = 1032
					IsPrimary = $true
				}
				[PSCustomObject]@{
					DeviceName = "\\.\DISPLAY2"; Left = 1920; Top = 0; Width = 1920; Height = 1080
					WorkAreaLeft = 1920; WorkAreaTop = 0; WorkAreaWidth = 1920; WorkAreaHeight = 1032
					IsPrimary = $false
				}
			)

			$result = Get-MonitorSpecs -MonitorInfo $mockMonitors -AsHashtable

			$result.Secondary.WorkX | Should -Be 1920
			$result.Secondary.WorkHeight | Should -Be 1032
		}
	}

	Context "Spatial Label Ordering" {
		# Labels must be a function of the PHYSICAL arrangement, not of Screen.AllScreens
		# enumeration order. With two displays there is exactly one non-primary monitor, so
		# "Secondary" is right whatever the order and the bug is invisible; these cases use
		# three displays, where enumeration order used to decide which panel became "Secondary"
		# versus "Monitor3" - arbitrarily, and able to swap between runs.
		It "Should label non-primary monitors left to right, not in enumeration order" {
			$result = Get-MonitorSpecs -MonitorInfo (New-MonitorFixture -Count 3) -AsHashtable

			$result.Primary.DeviceName | Should -Be (Get-ExpectedMonitorLabel 'Primary')
			$result.Secondary.DeviceName | Should -Be (Get-ExpectedMonitorLabel 'Secondary')
			$result.Monitor3.DeviceName | Should -Be (Get-ExpectedMonitorLabel 'Monitor3')
		}

		It "Should assign identical labels no matter what order the monitors are enumerated in" {
			$labelsPerOrder = foreach ($order in 'Physical', 'Scrambled', 'Reversed') {
				$specs = Get-MonitorSpecs -MonitorInfo (New-MonitorFixture -Count 3 -EnumerationOrder $order) -AsHashtable
				, @($specs.Secondary.DeviceName, $specs.Monitor3.DeviceName)
			}

			# Every enumeration order must produce the same (Secondary, Monitor3) pairing.
			@($labelsPerOrder | ForEach-Object { $_ -join '|' } | Select-Object -Unique).Count | Should -Be 1
		}

		It "Should keep Primary on the primary display even when it is not leftmost" {
			# DISPLAY2 sits to the LEFT of the primary display in the fixture.
			$result = Get-MonitorSpecs -MonitorInfo (New-MonitorFixture -Count 3) -AsHashtable

			$result.Primary.X | Should -Be 0
			$result.Secondary.X | Should -Be -1920
		}

		It "Should order displays stacked at the same X by their Top coordinate" {
			$stacked = @(
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY1'; Left = 0; Top = 0; Width = 3440; Height = 1440; IsPrimary = $true }
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY2'; Left = 0; Top = 1440; Width = 3440; Height = 1440; IsPrimary = $false }
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY3'; Left = 0; Top = -1440; Width = 3440; Height = 1440; IsPrimary = $false }
			)

			$result = Get-MonitorSpecs -MonitorInfo $stacked -AsHashtable

			# Topmost non-primary first: Top = -1440 beats Top = 1440.
			$result.Secondary.Y | Should -Be -1440
			$result.Monitor3.Y | Should -Be 1440
		}

		It "Should emit labels for every attached monitor beyond three" {
			$five = @(
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY1'; Left = 0; Top = 0; Width = 1920; Height = 1080; IsPrimary = $true }
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY2'; Left = 1920; Top = 0; Width = 1920; Height = 1080; IsPrimary = $false }
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY3'; Left = 3840; Top = 0; Width = 1920; Height = 1080; IsPrimary = $false }
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY4'; Left = 5760; Top = 0; Width = 1920; Height = 1080; IsPrimary = $false }
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY5'; Left = 7680; Top = 0; Width = 1920; Height = 1080; IsPrimary = $false }
			)

			$result = Get-MonitorSpecs -MonitorInfo $five -AsHashtable

			@($result.Keys | Sort-Object { Resolve-MonitorLabel -Label $_ }) |
				Should -Be @('Primary', 'Secondary', 'Monitor3', 'Monitor4', 'Monitor5')
			$result.Monitor5.DeviceName | Should -Be '\\.\DISPLAY5'
		}

		It "Should break a bounds tie deterministically for mirrored displays" {
			# Mirrored displays report identical bounds; DeviceName is the documented tie-break,
			# so the labeling must not depend on which one was enumerated first.
			$mirroredA = [PSCustomObject]@{ DeviceName = '\\.\DISPLAY2'; Left = 0; Top = 0; Width = 1920; Height = 1080; IsPrimary = $false }
			$mirroredB = [PSCustomObject]@{ DeviceName = '\\.\DISPLAY3'; Left = 0; Top = 0; Width = 1920; Height = 1080; IsPrimary = $false }
			$primary = [PSCustomObject]@{ DeviceName = '\\.\DISPLAY1'; Left = 0; Top = -1080; Width = 1920; Height = 1080; IsPrimary = $true }

			$oneOrder = Get-MonitorSpecs -MonitorInfo @($primary, $mirroredA, $mirroredB) -AsHashtable
			$otherOrder = Get-MonitorSpecs -MonitorInfo @($primary, $mirroredB, $mirroredA) -AsHashtable

			$oneOrder.Secondary.DeviceName | Should -Be '\\.\DISPLAY2'
			$otherOrder.Secondary.DeviceName | Should -Be '\\.\DISPLAY2'
		}
	}

	Context "Edge Cases" {
		It "Should handle empty monitor array gracefully" {
			# Function returns an object even with empty input (no primary found)
			{ Get-MonitorSpecs -MonitorInfo @() -ErrorAction SilentlyContinue } | Should -Not -Throw
		}

		It "Should label every display when none reports itself as primary" {
			# Get-MonitorInfo has been seen to report no primary during a display re-enumeration.
			$noPrimary = @(
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY1'; Left = 1920; Top = 0; Width = 1920; Height = 1080; IsPrimary = $false }
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY2'; Left = 0; Top = 0; Width = 1920; Height = 1080; IsPrimary = $false }
			)

			$result = Get-MonitorSpecs -MonitorInfo $noPrimary -AsHashtable

			$result.ContainsKey("Primary") | Should -Be $false
			$result.Secondary.DeviceName | Should -Be '\\.\DISPLAY2'
			$result.Monitor3.DeviceName | Should -Be '\\.\DISPLAY1'
		}
	}
}
