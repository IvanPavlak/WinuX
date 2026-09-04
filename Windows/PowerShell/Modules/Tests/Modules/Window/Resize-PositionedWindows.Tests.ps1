#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Resize-PositionedWindows.ps1"

	# The -InsetPercent default, stubbed so Mock can attach in a dot-sourced unit and so these
	# cases never read the live session configuration. It has its own suite.
	function Get-WindowInsetPercent { }
}

Describe "Resize-PositionedWindows" {
	BeforeEach {
		$script:WindowModuleTolerances = @{ PositionVerificationPx = 15 }
		Mock Get-WindowInsetPercent { 0.05 }
		$script:LastResizeWindowsResult = [PSCustomObject]@{
			ResizedCount  = 0
			SkippedCount  = 0
			FailedWindows = @()
		}
		Mock Resize-Windows {
			$script:LastResizeWindowsResult = [PSCustomObject]@{
				ResizedCount  = 0
				SkippedCount  = 0
				FailedWindows = @()
			}
		}
		Mock Write-Host { }
	}

	It "returns zeroed result when there are no tracked windows" {
		$script:PositionedWindowHandles = @()

		$result = Resize-PositionedWindows

		$result.ResizedCount | Should -Be 0
		$result.SkippedCount | Should -Be 0
		$result.FailedWindows.Count | Should -Be 0
	}

	It "aggregates resize results from tracked windows" {
		$script:PositionedWindowHandles = @(
			@{ Handle = [IntPtr]1; ExpectedX = 0; ExpectedY = 0; ExpectedWidth = 100; ExpectedHeight = 100 },
			@{ Handle = [IntPtr]2; ExpectedX = 0; ExpectedY = 0; ExpectedWidth = 100; ExpectedHeight = 100 }
		)
		Mock Resize-Windows {
			$script:LastResizeWindowsResult = [PSCustomObject]@{
				ResizedCount  = 1
				SkippedCount  = 2
				FailedWindows = @(@{ Handle = [IntPtr]9 })
			}
		}

		$result = Resize-PositionedWindows

		$result.ResizedCount | Should -Be 2
		$result.SkippedCount | Should -Be 4
		$result.FailedWindows.Count | Should -Be 2
		Should -Invoke Resize-Windows -Times 2
	}

	It "resizes only the tracked windows on the -DesktopNumbers desktops" {
		$script:PositionedWindowHandles = @(
			@{ Handle = [IntPtr]1; ExpectedX = 0; ExpectedY = 0; ExpectedWidth = 100; ExpectedHeight = 100; DesktopNumber = 1 },
			@{ Handle = [IntPtr]2; ExpectedX = 0; ExpectedY = 0; ExpectedWidth = 100; ExpectedHeight = 100; DesktopNumber = 2 },
			@{ Handle = [IntPtr]3; ExpectedX = 0; ExpectedY = 0; ExpectedWidth = 100; ExpectedHeight = 100; DesktopNumber = 2 }
		)

		$null = Resize-PositionedWindows -DesktopNumbers 2

		# A window on an already-snapped desktop sits at its full zone rect and must not be
		# pulled back to the inset.
		Should -Invoke Resize-Windows -Times 2 -Exactly
		Should -Invoke Resize-Windows -Times 0 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]1 }
	}

	It "treats a tracked window without a desktop number as desktop 1" {
		$script:PositionedWindowHandles = @(
			@{ Handle = [IntPtr]1; ExpectedX = 0; ExpectedY = 0; ExpectedWidth = 100; ExpectedHeight = 100 },
			@{ Handle = [IntPtr]2; ExpectedX = 0; ExpectedY = 0; ExpectedWidth = 100; ExpectedHeight = 100; DesktopNumber = 2 }
		)

		$null = Resize-PositionedWindows -DesktopNumbers 1

		Should -Invoke Resize-Windows -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]1 }
	}
}
