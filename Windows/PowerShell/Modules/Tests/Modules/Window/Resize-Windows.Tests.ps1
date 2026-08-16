#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Resize-Windows.ps1"
	# The real inset geometry, not a mock: target-bounds mode is only meaningful when the
	# bounds it hands to Set-WindowPosition are the ones the shared helper computes.
	. "$FunctionsPath\Get-InsetWindowBounds.ps1"

	# The two configuration-backed defaults, stubbed so Mock can attach in a dot-sourced unit
	# and so these cases never read the live session configuration (which would make the
	# expected sizes depend on the machine the suite runs on). Both have their own suites.
	function Resolve-ResizeWindowsPercent { param([object[]]$MonitorInfo) }
	function Get-WindowInsetPercent { }
}

Describe "Resize-Windows" {
	BeforeEach {
		$script:WindowModuleTolerances = @{ PositionVerificationPx = 15 }
		Mock Resolve-ResizeWindowsPercent { 70 }
		Mock Get-WindowInsetPercent { 0.05 }
		Mock Ensure-WindowsFormsLoaded { }
		Mock Get-MonitorInfo { @() }
		Mock Clear-WindowCache { }
		Mock Get-CachedWindows { @() }
		Mock Set-WindowPosition { $true }
		Mock Write-Host { }
		Mock Write-Warning { }
	}

	It "returns early when monitor info is not available" {
		Resize-Windows -Percent 80

		Should -Invoke Get-MonitorInfo -Times 1
		Should -Invoke Write-Warning -Times 1
		Should -Invoke Get-CachedWindows -Times 0
	}

	It "stores summary in script state without pipeline output" {
		Mock Get-MonitorInfo {
			@([PSCustomObject]@{
					Left = 0; Top = 0; Right = 1920; Bottom = 1080
					WorkAreaLeft = 0; WorkAreaTop = 0; WorkAreaWidth = 1920; WorkAreaHeight = 1080
					IsPrimary = $true; DeviceName = 'DISPLAY1'
				})
		}
		Mock Get-CachedWindows {
			@([PSCustomObject]@{
					Handle = [IntPtr]1; Title = 'Test Window'; ProcessName = 'TestApp'
					Width = 800; Height = 600; Left = 100; Top = 100
				})
		}

		$result = @(Resize-Windows -WindowHandle ([IntPtr]1))
		$state = $script:LastResizeWindowsResult

		$result.Count | Should -Be 0
		$state.ResizedCount | Should -Be 1
		$state.SkippedCount | Should -Be 0
		$state.FailedWindows.Count | Should -Be 0
	}

	It "delegates filtering to Get-WindowHandle when ProcessName is provided" {
		Mock Get-MonitorInfo {
			@([PSCustomObject]@{
					Left = 0; Top = 0; Right = 1920; Bottom = 1080
					WorkAreaLeft = 0; WorkAreaTop = 0; WorkAreaWidth = 1920; WorkAreaHeight = 1080
					IsPrimary = $true; DeviceName = 'DISPLAY1'
				})
		}
		# Get-WindowHandle is the shared filtering path (same as Move-Windows); mocking it
		# verifies Resize-Windows delegates rather than re-enumerating via Get-CachedWindows.
		Mock Get-WindowHandle {
			@([PSCustomObject]@{
					Handle = [IntPtr]2; Title = 'Chrome'; ProcessName = 'chrome'
					Width = 800; Height = 600; Left = 100; Top = 100
				})
		}

		Resize-Windows -ProcessName "chrome"

		Should -Invoke Get-WindowHandle -Times 1 -ParameterFilter { $ProcessName -eq 'chrome' }
		Should -Invoke Get-CachedWindows -Times 0
		Should -Invoke Set-WindowPosition -Times 1 -ParameterFilter { $WindowHandle -eq [IntPtr]2 }
	}

	Context "Single-handle mode overhead and output" {
		BeforeEach {
			Mock Get-MonitorInfo {
				@([PSCustomObject]@{
						Left = 0; Top = 0; Right = 1920; Bottom = 1080
						WorkAreaLeft = 0; WorkAreaTop = 0; WorkAreaWidth = 1920; WorkAreaHeight = 1080
						IsPrimary = $true; DeviceName = 'DISPLAY1'
					})
			}
			Mock Get-CachedWindows {
				@([PSCustomObject]@{
						Handle = [IntPtr]1; Title = 'Test Window'; ProcessName = 'TestApp'
						Width = 800; Height = 600; Left = 100; Top = 100
					})
			}
		}

		It "does not force a cache refresh per call (tight-loop callers pay 10-30ms per clear)" {
			$null = Resize-Windows -WindowHandle ([IntPtr]1)

			Should -Invoke Clear-WindowCache -Times 0
			Should -Invoke Get-CachedWindows -Times 1 -Exactly
		}

		It "stays quiet in single-handle percent mode (one line per window spammed workspace opens)" {
			Mock Write-LogSuccess { }

			$null = Resize-Windows -WindowHandle ([IntPtr]1)

			Should -Invoke Write-LogSuccess -Times 0
		}

		It "still prints the summary for the user-facing resize-all invocation" {
			Mock Write-LogSuccess { }

			$null = Resize-Windows

			Should -Invoke Write-LogSuccess -Times 1 -Exactly -ParameterFilter { $Message -like "*window(s) to*" }
		}
	}

	Context "Configured default percentage" {
		# Set-WorkspaceWindowLayout's normalization and retry passes call Resize-Windows with no
		# -Percent at all, so the configured per-display default is the only way those paths can
		# differ between a laptop panel and a wide monitor.
		BeforeEach {
			Mock Get-MonitorInfo {
				@([PSCustomObject]@{
						Left = 0; Top = 0; Right = 1920; Bottom = 1080
						WorkAreaLeft = 0; WorkAreaTop = 0; WorkAreaWidth = 1920; WorkAreaHeight = 1080
						IsPrimary = $true; DeviceName = 'DISPLAY1'
					})
			}
			Mock Get-CachedWindows {
				@([PSCustomObject]@{
						Handle = [IntPtr]1; Title = 'Test Window'; ProcessName = 'TestApp'
						Width = 800; Height = 600; Left = 100; Top = 100
					})
			}
		}

		It "resolves the percentage when the caller supplies none" {
			$null = Resize-Windows -WindowHandle ([IntPtr]1)

			Should -Invoke Resolve-ResizeWindowsPercent -Times 1 -Exactly
		}

		It "scales by the resolved percentage" {
			Mock Resolve-ResizeWindowsPercent { 50 }

			$null = Resize-Windows -WindowHandle ([IntPtr]1)

			Should -Invoke Set-WindowPosition -Times 1 -Exactly -ParameterFilter { $Width -eq 400 -and $Height -eq 300 }
		}

		It "leaves an explicit -Percent alone" {
			Mock Resolve-ResizeWindowsPercent { 50 }

			$null = Resize-Windows -WindowHandle ([IntPtr]1) -Percent 80

			Should -Invoke Resolve-ResizeWindowsPercent -Times 0 -Exactly
			Should -Invoke Set-WindowPosition -Times 1 -Exactly -ParameterFilter { $Width -eq 640 -and $Height -eq 480 }
		}

		It "does not resolve a percentage in target-bounds mode" {
			# Target-bounds mode never scales by percent, so it must not pay for the monitor
			# query the resolver would otherwise make.
			$null = Resize-Windows -WindowHandle ([IntPtr]1) -TargetX 0 -TargetY 0 -TargetWidth 1000 -TargetHeight 800

			Should -Invoke Resolve-ResizeWindowsPercent -Times 0 -Exactly
		}

		It "takes the inset from the configured default in target-bounds mode" {
			Mock Get-WindowInsetPercent { 0.1 }

			$null = Resize-Windows -WindowHandle ([IntPtr]1) -TargetX 0 -TargetY 0 -TargetWidth 1000 -TargetHeight 800

			Should -Invoke Get-WindowInsetPercent -Times 1 -Exactly
			Should -Invoke Set-WindowPosition -Times 1 -Exactly -ParameterFilter { $Width -eq 800 -and $Height -eq 640 }
		}

		It "leaves an explicit -InsetPercent alone" {
			# Center-Windows depends on this: -InsetPercent 0 is exact placement, not a default.
			Mock Get-WindowInsetPercent { 0.1 }

			$null = Resize-Windows -WindowHandle ([IntPtr]1) -TargetX 0 -TargetY 0 -TargetWidth 1000 -TargetHeight 800 -InsetPercent 0

			Should -Invoke Get-WindowInsetPercent -Times 0 -Exactly
			Should -Invoke Set-WindowPosition -Times 1 -Exactly -ParameterFilter { $Width -eq 1000 -and $Height -eq 800 }
		}
	}
}
