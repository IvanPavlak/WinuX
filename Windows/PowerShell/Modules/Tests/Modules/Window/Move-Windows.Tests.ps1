#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Move-Windows.ps1"
	# -Monitor resolution is delegated to Resolve-TargetMonitor; load the real helper so the
	# index/label/device-name rules are exercised rather than stubbed.
	. "$FunctionsPath\Resolve-TargetMonitor.ps1"
	# The verification sweep re-checks windows through Get-WindowDesktopIndex and retries
	# stragglers through Move-WindowToVirtualDesktop; load them so Mock can attach.
	. "$FunctionsPath\Get-WindowDesktopIndex.ps1"
	. "$FunctionsPath\Move-WindowToVirtualDesktop.ps1"

	# The rest of the Window module's virtual-desktop adapter, stubbed so Mock attaches in this
	# script scope instead of the module.
	function Get-VirtualDesktopCount { 1 }
	function Get-CurrentVirtualDesktopIndex { 0 }
	function Switch-VirtualDesktop { param([int]$Index, [int]$TimeoutMs, [int]$MaxAttempts) $true }
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
		# By default the in-loop check and the sweep find every window where the pass left it
		# (tests target Virtual Desktop 1, i.e. index 0); sweep tests override this to plant
		# stragglers.
		Mock Get-WindowDesktopIndex { 0 }
		Mock Move-WindowToVirtualDesktop { $true }
	}

	It "returns early when virtual desktop module is unavailable" {
		{ Move-Windows -VirtualDesktop 1 } | Should -Not -Throw

		Should -Invoke Import-VirtualDesktopModule -Times 1
		Should -Invoke Write-LogError -Times 1
	}

	It "switches focus to the target desktop after moving windows" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-VirtualDesktopCount { 2 }
		Mock Switch-VirtualDesktop { $true }

		{ Move-Windows -VirtualDesktop 1 } | Should -Not -Throw

		Should -Invoke Switch-VirtualDesktop -Times 1 -ParameterFilter { $Index -eq 0 }
	}

	It "repositions windows on the target monitor when -Monitor is specified" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-VirtualDesktopCount { 2 }
		Mock Switch-VirtualDesktop { $true }
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
		Mock Get-VirtualDesktopCount { 2 }
		Mock Switch-VirtualDesktop { $true }
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

	It "verification sweep recovers a window whose already-on-desktop read was stale" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-VirtualDesktopCount { 2 }
		Mock Switch-VirtualDesktop { $true }
		Mock Test-LogVerbose { $false }
		Mock Write-LogWarning { }
		Mock Write-LogList { }
		Mock Write-LogSuccess { }
		Mock Get-CachedWindows {
			@(
				[PSCustomObject]@{
					Handle = [IntPtr]3333; Title = 'Straggler'; ProcessName = 'firefox'
					Left = 0; Top = 0; Width = 800; Height = 600
				}
			)
		}
		# The in-loop check (first read) says the window is already on the target (index 0)...
		# ...but the first convergence round (second read) finds it on another desktop; the retry
		# lands it, and the next round confirms it is home.
		$script:desktopReads = 0
		Mock Get-WindowDesktopIndex {
			$script:desktopReads++
			if ($script:desktopReads -eq 2) { 1 } else { 0 }
		}

		{ Move-Windows -VirtualDesktop 1 } | Should -Not -Throw

		Should -Invoke Move-WindowToVirtualDesktop -Times 1 -Exactly -ParameterFilter {
			$WindowHandle -eq [IntPtr]3333 -and $DesktopNumber -eq 0
		}
		# The recovery is counted as a move, not as already-there, and nothing is reported failed.
		Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -match 'Moved 1 window' }
		Should -Invoke Write-LogWarning -Times 0 -ParameterFilter { $Message -match 'could not be moved' }
	}

	It "convergence rounds pick up a window the first pass never enumerated" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-VirtualDesktopCount { 2 }
		Mock Switch-VirtualDesktop { $true }
		Mock Test-LogVerbose { $false }
		Mock Write-LogWarning { }
		Mock Write-LogList { }
		Mock Write-LogSuccess { }
		# First enumeration: nothing eligible (the window still had no title while it loaded).
		# Every later enumeration (the convergence rounds) sees it.
		$script:enumerations = 0
		Mock Get-CachedWindows {
			$script:enumerations++
			if ($script:enumerations -eq 1) { @() }
			else {
				@(
					[PSCustomObject]@{
						Handle = [IntPtr]5555; Title = 'Late Bloomer'; ProcessName = 'Code'
						Left = 0; Top = 0; Width = 800; Height = 600
					}
				)
			}
		}
		$script:lateReads = 0
		Mock Get-WindowDesktopIndex {
			$script:lateReads++
			if ($script:lateReads -eq 1) { 1 } else { 0 }
		}

		{ Move-Windows -VirtualDesktop 1 } | Should -Not -Throw

		# Never seen by the per-window pass, still moved by the convergence round and counted.
		Should -Invoke Move-WindowToVirtualDesktop -Times 1 -Exactly -ParameterFilter {
			$WindowHandle -eq [IntPtr]5555 -and $DesktopNumber -eq 0
		}
		Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -match 'Moved 1 window' }
	}

	It "convergence rounds stop as soon as a round finds every window on the target" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-VirtualDesktopCount { 2 }
		Mock Switch-VirtualDesktop { $true }
		Mock Get-CachedWindows {
			@(
				[PSCustomObject]@{
					Handle = [IntPtr]6666; Title = 'Settled'; ProcessName = 'notepad'
					Left = 0; Top = 0; Width = 800; Height = 600
				}
			)
		}
		Mock Get-WindowDesktopIndex { 0 }

		{ Move-Windows -VirtualDesktop 1 } | Should -Not -Throw

		# The in-loop check plus one check in the single convergence round; no second round, no retry.
		Should -Invoke Get-WindowDesktopIndex -Times 2 -Exactly
		Should -Invoke Move-WindowToVirtualDesktop -Times 0
	}

	It "verification sweep reclassifies a persistent straggler as a failure instead of reporting a clean pass" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-VirtualDesktopCount { 2 }
		Mock Switch-VirtualDesktop { $true }
		Mock Test-LogVerbose { $false }
		Mock Write-LogWarning { }
		Mock Write-LogList { }
		Mock Write-LogSuccess { }
		Mock Get-CachedWindows {
			@(
				[PSCustomObject]@{
					Handle = [IntPtr]4444; Title = 'Stuck Window'; ProcessName = 'WindowsTerminal'
					Left = 0; Top = 0; Width = 800; Height = 600
				}
			)
		}
		# In-loop check reports the window elsewhere, so the move pass runs and claims success -
		# the upstream wrong-window fallback makes exactly this claim while the window stays put.
		Mock Get-WindowDesktopIndex { 1 }
		$script:moveAttempts = 0
		Mock Move-WindowToVirtualDesktop {
			$script:moveAttempts++
			if ($script:moveAttempts -eq 1) { $true } else { $false }
		}

		{ Move-Windows -VirtualDesktop 1 } | Should -Not -Throw

		# One in-loop move plus the two convergence retries a straggler is allowed, then the
		# window is reported as failed - never as a clean pass.
		Should -Invoke Move-WindowToVirtualDesktop -Times 3 -Exactly
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'could not be moved' }
		Should -Invoke Write-LogSuccess -Times 0 -ParameterFilter { $Message -match 'Moved' }
	}

	It "returns early when monitor index is out of range" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-VirtualDesktopCount { 2 }
		Mock Get-MonitorInfo {
			@(
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY1'; IsPrimary = $true },
				[PSCustomObject]@{ DeviceName = '\\.\DISPLAY2'; IsPrimary = $false }
			)
		}
		Mock Switch-VirtualDesktop { $true }

		{ Move-Windows -VirtualDesktop 1 -Monitor 5 } | Should -Not -Throw

		Should -Invoke Write-LogError -Times 1
		Should -Invoke Switch-VirtualDesktop -Times 0
	}
}
