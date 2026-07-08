#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force

	# Also dot-source individual functions for script-scoped variable access in tracking tests
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "Window\Functions"
	. "$FunctionsPath\Initialize-PositionedWindowTracking.ps1"
	. "$FunctionsPath\Add-PositionedWindow.ps1"
	. "$FunctionsPath\Test-PositionedWindow.ps1"
	. "$FunctionsPath\Get-PositionedWindowCount.ps1"
}

Describe "Positioned Window Tracking" {
	BeforeEach {
		# Clear tracking before each test
		Initialize-PositionedWindowTracking
	}

	Context "Initialize-PositionedWindowTracking" {
		It "Should initialize empty tracking" {
			Initialize-PositionedWindowTracking

			$count = Get-PositionedWindowCount
			$count | Should -Be 0
		}

		It "Should clear existing tracking when called" {
			Add-PositionedWindow -WindowHandle ([IntPtr]123) -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "Test"
			Get-PositionedWindowCount | Should -Be 1

			Initialize-PositionedWindowTracking

			Get-PositionedWindowCount | Should -Be 0
		}

		It "Should be idempotent when called multiple times" {
			Initialize-PositionedWindowTracking
			Initialize-PositionedWindowTracking
			Initialize-PositionedWindowTracking

			Get-PositionedWindowCount | Should -Be 0
		}
	}

	Context "Add-PositionedWindow" {
		It "Should add a window to tracking with all expected properties" {
			$handle = [IntPtr]12345

			Add-PositionedWindow -WindowHandle $handle -ExpectedX 100 -ExpectedY 200 -ExpectedWidth 800 -ExpectedHeight 600 -WindowTitle "TestWindow" -DesktopNumber 0

			Get-PositionedWindowCount | Should -Be 1
		}

		It "Should allow adding multiple distinct windows" {
			Add-PositionedWindow -WindowHandle ([IntPtr]1) -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "Window1"
			Add-PositionedWindow -WindowHandle ([IntPtr]2) -ExpectedX 100 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "Window2"
			Add-PositionedWindow -WindowHandle ([IntPtr]3) -ExpectedX 200 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "Window3"

			Get-PositionedWindowCount | Should -Be 3
		}

		It "Should update existing window entry instead of duplicating" {
			$handle = [IntPtr]999

			Add-PositionedWindow -WindowHandle $handle -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "First"
			Add-PositionedWindow -WindowHandle $handle -ExpectedX 200 -ExpectedY 200 -ExpectedWidth 400 -ExpectedHeight 400 -WindowTitle "Updated"

			Get-PositionedWindowCount | Should -Be 1
		}

		It "Should handle windows on different virtual desktops" {
			Add-PositionedWindow -WindowHandle ([IntPtr]1) -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "Desktop0Window" -DesktopNumber 0
			Add-PositionedWindow -WindowHandle ([IntPtr]2) -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "Desktop1Window" -DesktopNumber 1
			Add-PositionedWindow -WindowHandle ([IntPtr]3) -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "Desktop2Window" -DesktopNumber 2

			Get-PositionedWindowCount | Should -Be 3
		}
	}

	Context "Test-PositionedWindow" {
		It "Should return false for untracked window" {
			$result = Test-PositionedWindow -WindowHandle ([IntPtr]99999)

			$result | Should -Be $false
		}

		It "Should return true for tracked window" {
			$handle = [IntPtr]12345
			Add-PositionedWindow -WindowHandle $handle -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "Test"

			$result = Test-PositionedWindow -WindowHandle $handle

			$result | Should -Be $true
		}

		It "Should distinguish between different window handles" {
			$handle1 = [IntPtr]111
			$handle2 = [IntPtr]222
			Add-PositionedWindow -WindowHandle $handle1 -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "Window1"

			Test-PositionedWindow -WindowHandle $handle1 | Should -Be $true
			Test-PositionedWindow -WindowHandle $handle2 | Should -Be $false
		}

		It "Should return false when tracking is not initialized" {
			$script:PositionedWindowHandles = $null

			$result = Test-PositionedWindow -WindowHandle ([IntPtr]123)

			$result | Should -Be $false
		}

		It "Should handle zero IntPtr handle" {
			$result = Test-PositionedWindow -WindowHandle ([IntPtr]::Zero)

			$result | Should -Be $false
		}
	}

	Context "Get-PositionedWindowCount" {
		It "Should return 0 when no windows tracked" {
			Initialize-PositionedWindowTracking

			Get-PositionedWindowCount | Should -Be 0
		}

		It "Should return correct count after adding windows" {
			Add-PositionedWindow -WindowHandle ([IntPtr]1) -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "W1"
			Add-PositionedWindow -WindowHandle ([IntPtr]2) -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "W2"

			Get-PositionedWindowCount | Should -Be 2
		}

		It "Should return 0 when tracking variable is null" {
			$script:PositionedWindowHandles = $null

			Get-PositionedWindowCount | Should -Be 0
		}
	}

	Context "Complete Workflow" {
		It "Should support complete track-test-clear workflow" {
			# Initialize
			Initialize-PositionedWindowTracking
			Get-PositionedWindowCount | Should -Be 0

			# Add windows
			$handles = @([IntPtr]100, [IntPtr]200, [IntPtr]300)
			foreach ($i in 0..2) {
				Add-PositionedWindow -WindowHandle $handles[$i] -ExpectedX ($i * 100) -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "Window$i"
			}
			Get-PositionedWindowCount | Should -Be 3

			# Test windows
			foreach ($handle in $handles) {
				Test-PositionedWindow -WindowHandle $handle | Should -Be $true
			}
			Test-PositionedWindow -WindowHandle ([IntPtr]999) | Should -Be $false

			# Clear
			Initialize-PositionedWindowTracking
			Get-PositionedWindowCount | Should -Be 0
			foreach ($handle in $handles) {
				Test-PositionedWindow -WindowHandle $handle | Should -Be $false
			}
		}
	}
}
