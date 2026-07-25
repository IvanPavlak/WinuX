#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Center-Windows.ps1"
	# Center-Windows filters via Get-WindowHandle (same path as Move-Windows); load the real
	# helper so filtering is exercised against the mocked Get-CachedWindows.
	. "$FunctionsPath\Get-WindowHandle.ps1"
	# -Monitor resolution is delegated to Resolve-TargetMonitor (shared with Move-Windows).
	. "$FunctionsPath\Resolve-TargetMonitor.ps1"
}

Describe "Center-Windows" {
	BeforeEach {
		$script:WindowModuleTolerances = @{ PositionVerificationPx = 15 }
		Mock Ensure-WindowsFormsLoaded { }
		Mock Get-MonitorInfo { @() }
		Mock Get-CachedWindows { @() }
		Mock Clear-WindowCache { }
		Mock Write-Warning { }
		Mock Write-Host { }

		# Placement is delegated to Resize-Windows in target-bounds mode; mock it and report
		# a successful resize so Center-Windows counts the window as centered.
		Mock Resize-Windows {
			$script:LastResizeWindowsResult = [PSCustomObject]@{
				ResizedCount  = 1
				SkippedCount  = 0
				FailedWindows = @()
			}
		}
	}

	It "returns early when no monitors are detected" {
		Center-Windows

		Should -Invoke Get-MonitorInfo -Times 1
		Should -Invoke Write-Warning -Times 1
		Should -Invoke Get-CachedWindows -Times 0
		Should -Invoke Resize-Windows -Times 0
	}

	Context "-OnPrimary" {
		BeforeEach {
			# Primary on the left, secondary on the right; both 1920x1080 with a
			# 40px taskbar reserved at the bottom of the work area.
			$primary = [PSCustomObject]@{
				DeviceName = '\\.\DISPLAY1'
				Left = 0; Top = 0; Right = 1920; Bottom = 1080
				Width = 1920; Height = 1080
				WorkAreaLeft = 0; WorkAreaTop = 0; WorkAreaRight = 1920; WorkAreaBottom = 1040
				WorkAreaWidth = 1920; WorkAreaHeight = 1040
				IsPrimary  = $true
			}
			$secondary = [PSCustomObject]@{
				DeviceName = '\\.\DISPLAY2'
				Left = 1920; Top = 0; Right = 3840; Bottom = 1080
				Width = 1920; Height = 1080
				WorkAreaLeft = 1920; WorkAreaTop = 0; WorkAreaRight = 3840; WorkAreaBottom = 1040
				WorkAreaWidth = 1920; WorkAreaHeight = 1040
				IsPrimary  = $false
			}

			Mock Get-MonitorInfo { @($primary, $secondary) }
			Mock Get-WindowDisplayName { 'Windows Terminal' }

			# A terminal window currently living on the secondary monitor.
			Mock Get-CachedWindows {
				@([PSCustomObject]@{
						Handle      = [IntPtr]1
						Title       = 'PowerShell'
						ProcessName = 'WindowsTerminal'
						Left = 2200; Top = 200; Width = 800; Height = 600
					})
			}
		}

		It "centers a secondary-monitor window onto the primary work area" {
			# Defaults: 40% width => 768, 50% height => 520.
			# Primary work area (0,0)-(1920,1040): X = (1920-768)/2 = 576, Y = (1040-520)/2 = 260.
			# Placement is delegated to Resize-Windows in exact (inset 0) target-bounds mode.
			Center-Windows -ProcessName "WindowsTerminal" -OnPrimary

			Should -Invoke Resize-Windows -Times 1 -ParameterFilter {
				$WindowHandle -eq [IntPtr]1 -and
				$TargetX -eq 576 -and $TargetY -eq 260 -and
				$TargetWidth -eq 768 -and $TargetHeight -eq 520 -and
				$InsetPercent -eq 0
			}
		}

		It "leaves the window on its current (secondary) monitor without -OnPrimary" {
			# Without -OnPrimary the window stays on the secondary monitor, whose
			# work area starts at X=1920, so X = 1920 + (1920-768)/2 = 2496.
			Center-Windows -ProcessName "WindowsTerminal"

			Should -Invoke Resize-Windows -Times 1 -ParameterFilter {
				$TargetX -eq 2496
			}
		}
	}

	Context "-Monitor" {
		BeforeEach {
			$primary = [PSCustomObject]@{
				DeviceName = '\\.\DISPLAY1'
				Left = 0; Top = 0; Right = 1920; Bottom = 1080
				Width = 1920; Height = 1080
				WorkAreaLeft = 0; WorkAreaTop = 0; WorkAreaRight = 1920; WorkAreaBottom = 1040
				WorkAreaWidth = 1920; WorkAreaHeight = 1040
				IsPrimary  = $true
			}
			$secondary = [PSCustomObject]@{
				DeviceName = '\\.\DISPLAY2'
				Left = 1920; Top = 0; Right = 3840; Bottom = 1080
				Width = 1920; Height = 1080
				WorkAreaLeft = 1920; WorkAreaTop = 0; WorkAreaRight = 3840; WorkAreaBottom = 1040
				WorkAreaWidth = 1920; WorkAreaHeight = 1040
				IsPrimary  = $false
			}

			Mock Get-MonitorInfo { @($primary, $secondary) }
			Mock Get-MonitorSpecs {
				[PSCustomObject]@{
					Primary   = [PSCustomObject]@{ X = 0; Y = 0; Width = 1920; Height = 1080 }
					Secondary = [PSCustomObject]@{ X = 1920; Y = 0; Width = 1920; Height = 1080 }
				}
			}
			Mock Get-WindowDisplayName { 'Chrome' }
			Mock Write-LogError { }

			# A window currently living on the secondary monitor.
			Mock Get-CachedWindows {
				@([PSCustomObject]@{
						Handle      = [IntPtr]2
						Title       = 'New Tab - Google Chrome'
						ProcessName = 'chrome'
						Left = 2200; Top = 200; Width = 800; Height = 600
					})
			}
		}

		It "pulls a secondary-monitor window onto the monitor named by index" {
			# Monitor 1 is the primary work area: X = (1920-768)/2 = 576, Y = (1040-520)/2 = 260.
			Center-Windows -ProcessName "chrome" -Monitor 1

			Should -Invoke Resize-Windows -Times 1 -ParameterFilter {
				$TargetX -eq 576 -and $TargetY -eq 260
			}
		}

		It "accepts a monitor label as well as an index" {
			Center-Windows -ProcessName "chrome" -Monitor "Primary"

			Should -Invoke Resize-Windows -Times 1 -ParameterFilter {
				$TargetX -eq 576
			}
		}

		It "keeps a window on the target monitor it already occupies" {
			# Secondary work area starts at X=1920 => X = 1920 + (1920-768)/2 = 2496.
			Center-Windows -ProcessName "chrome" -Monitor 2

			Should -Invoke Resize-Windows -Times 1 -ParameterFilter {
				$TargetX -eq 2496
			}
		}

		It "reports an error and centers nothing when the monitor cannot be resolved" {
			Center-Windows -ProcessName "chrome" -Monitor "Monitor9"

			Should -Invoke Write-LogError -Times 1
			Should -Invoke Resize-Windows -Times 0
		}

		It "treats an empty monitor specifier as no targeting" {
			# Reset-Windows passes no -Monitor when none is configured, but an empty string
			# must not abort the pass either: the window stays on its current monitor.
			Center-Windows -ProcessName "chrome" -Monitor ""

			Should -Invoke Write-LogError -Times 0
			Should -Invoke Resize-Windows -Times 1 -ParameterFilter {
				$TargetX -eq 2496
			}
		}
	}
}
