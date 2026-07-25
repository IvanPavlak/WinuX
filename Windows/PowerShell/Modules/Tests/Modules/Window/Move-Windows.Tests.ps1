#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Move-Windows.ps1"
	# -Monitor resolution is delegated to Resolve-TargetMonitor; load the real helper so the
	# index/label/device-name rules are exercised rather than stubbed.
	. "$FunctionsPath\Resolve-TargetMonitor.ps1"

	# VirtualDesktop cmdlets come from an optional external module absent on CI runners.
	# Stub the ones these tests mock so Mock can attach (no-op where the real module exists).
	if (-not (Get-Command Get-DesktopCount -ErrorAction SilentlyContinue)) {
		function Get-DesktopCount { [CmdletBinding()] param() }
		function Switch-Desktop { [CmdletBinding()] param($Desktop) }
		function Get-DesktopFromWindow { [CmdletBinding()] param($Hwnd) }
		function Get-DesktopIndex { [CmdletBinding()] param([Parameter(Position = 0)]$Desktop) }
	}
}

Describe "Move-Windows" {
	BeforeEach {
		Mock Import-VirtualDesktopModule { $false }
		Mock Write-Host { }
		Mock Write-LogError { }
		Mock Clear-WindowCache { }
		Mock Get-CachedWindows { @() }
		Mock Get-MonitorInfo { @() }
		Mock Get-MonitorSpecs { $null }
		Mock Set-WindowPosition { $true }
		Mock Get-WindowDisplayName { 'Test Window' }
		# Monitor placement is verified via Wait-WindowRect (real GetWindowRect is unavailable
		# here); report the requested bounds as verified unless a test overrides this.
		Mock Wait-WindowRect {
			[PSCustomObject]@{
				Verified = $true; X = $ExpectedX; Y = $ExpectedY
				Width = $ExpectedWidth; Height = $ExpectedHeight; ElapsedMs = 0
			}
		}
		Mock Invoke-WithOptionalRetry {
			param($EnableRetry, $ScriptBlock, $MaxAttempts, $InitialDelayMs)
			& $ScriptBlock
		}
	}

	It "returns early when virtual desktop module is unavailable" {
		{ Move-Windows -VirtualDesktop 1 } | Should -Not -Throw

		Should -Invoke Import-VirtualDesktopModule -Times 1
		Should -Invoke Write-LogError -Times 1
	}

	It "switches focus to the target desktop after moving windows" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-DesktopCount { 2 }
		Mock Switch-Desktop { }

		{ Move-Windows -VirtualDesktop 1 } | Should -Not -Throw

		Should -Invoke Switch-Desktop -Times 1 -ParameterFilter { $Desktop -eq 0 }
	}

	It "repositions windows on the target monitor when -Monitor is specified" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-DesktopCount { 2 }
		Mock Get-DesktopFromWindow { [PSCustomObject]@{ Name = 'Desktop1' } }
		Mock Get-DesktopIndex { 0 }
		Mock Switch-Desktop { }
		Mock Get-CachedWindows {
			@(
				[PSCustomObject]@{
					Handle      = [IntPtr]1111
					Title       = 'Test Window'
					ProcessName = 'notepad'
					Left        = 200
					Top         = 200
					Width       = 800
					Height      = 600
				}
			)
		}
		Mock Get-MonitorInfo {
			@(
				[PSCustomObject]@{
					DeviceName     = '\\.\DISPLAY1'
					Left           = 0
					Top            = 0
					Right          = 1920
					Bottom         = 1080
					Width          = 1920
					Height         = 1080
					WorkAreaLeft   = 0
					WorkAreaTop    = 0
					WorkAreaRight  = 1920
					WorkAreaBottom = 1040
					WorkAreaWidth  = 1920
					WorkAreaHeight = 1040
					IsPrimary      = $true
				},
				[PSCustomObject]@{
					DeviceName     = '\\.\DISPLAY2'
					Left           = 1920
					Top            = 0
					Right          = 3840
					Bottom         = 1080
					Width          = 1920
					Height         = 1080
					WorkAreaLeft   = 1920
					WorkAreaTop    = 0
					WorkAreaRight  = 3840
					WorkAreaBottom = 1040
					WorkAreaWidth  = 1920
					WorkAreaHeight = 1040
					IsPrimary      = $false
				}
			)
		}

		{ Move-Windows -VirtualDesktop 1 -Monitor 2 } | Should -Not -Throw

		# Relative placement must be PRESERVED, not rounded to a work-area corner.
		# Source work area 1920x1040, window 800x600 at (200,200):
		#   relativeX = 200 / (1920-800) = 0.1786 -> 1920 + round(0.1786 * 1120) = 2120
		#   relativeY = 200 / (1040-600) = 0.4545 ->    0 + round(0.4545 *  440) =  200
		# Clamping with int literals ([math]::Min(1, $x)) rounds the fraction to 0/1 and
		# yields the corner (1920, 0) instead - this asserts the double-literal clamp.
		Should -Invoke Set-WindowPosition -Times 1 -ParameterFilter {
			$WindowHandle -eq [IntPtr]1111 -and $X -eq 2120 -and $Y -eq 200
		}
	}

	It "re-applies the monitor placement when the window does not hold its position" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-DesktopCount { 2 }
		Mock Get-DesktopFromWindow { [PSCustomObject]@{ Name = 'Desktop1' } }
		Mock Get-DesktopIndex { 0 }
		Mock Switch-Desktop { }
		Mock Test-LogVerbose { $false }
		Mock Write-LogWarning { }
		Mock Write-LogList { }
		Mock Write-LogSuccess { }
		# Placement never sticks: something keeps moving the window back.
		Mock Wait-WindowRect {
			[PSCustomObject]@{ Verified = $false; X = 100; Y = 100; Width = 800; Height = 600; ElapsedMs = 150 }
		}
		Mock Get-CachedWindows {
			@(
				[PSCustomObject]@{
					Handle = [IntPtr]2222; Title = 'Drifting Window'; ProcessName = 'chrome'
					Left = 200; Top = 200; Width = 800; Height = 600
				}
			)
		}
		Mock Get-MonitorInfo {
			@(
				[PSCustomObject]@{
					DeviceName = '\\.\DISPLAY1'; Left = 0; Top = 0; Right = 1920; Bottom = 1080
					Width = 1920; Height = 1080
					WorkAreaLeft = 0; WorkAreaTop = 0; WorkAreaRight = 1920; WorkAreaBottom = 1040
					WorkAreaWidth = 1920; WorkAreaHeight = 1040; IsPrimary = $true
				},
				[PSCustomObject]@{
					DeviceName = '\\.\DISPLAY2'; Left = 1920; Top = 0; Right = 3840; Bottom = 1080
					Width = 1920; Height = 1080
					WorkAreaLeft = 1920; WorkAreaTop = 0; WorkAreaRight = 3840; WorkAreaBottom = 1040
					WorkAreaWidth = 1920; WorkAreaHeight = 1040; IsPrimary = $false
				}
			)
		}

		{ Move-Windows -VirtualDesktop 1 -Monitor 2 } | Should -Not -Throw

		# Two attempts, and the unstuck window is reported instead of counted as moved.
		Should -Invoke Set-WindowPosition -Times 2
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter {
			$Message -match 'did not stay on monitor'
		}
	}

	It "returns early when monitor index is out of range" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-DesktopCount { 2 }
		Mock Get-MonitorInfo {
			@(
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY1'; IsPrimary = $true },
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY2'; IsPrimary = $false }
			)
		}
		Mock Switch-Desktop { }

		{ Move-Windows -VirtualDesktop 1 -Monitor 5 } | Should -Not -Throw

		Should -Invoke Write-LogError -Times 1
		Should -Invoke Switch-Desktop -Times 0
	}
}
