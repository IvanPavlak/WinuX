#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
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

	Context "Edge Cases" {
		It "Should handle empty monitor array gracefully" {
			# Function returns an object even with empty input (no primary found)
			{ Get-MonitorSpecs -MonitorInfo @() -ErrorAction SilentlyContinue } | Should -Not -Throw
		}
	}
}
