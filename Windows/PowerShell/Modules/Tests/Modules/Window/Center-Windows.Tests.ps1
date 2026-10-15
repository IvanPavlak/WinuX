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

	# Stands in for the live window list: a window the mocked Resize-Windows placed is reported
	# at the bounds it was given, so the convergence rounds see it holding them. A test that
	# wants a window to drift returns its own list instead.
	$script:AsPlaced = {
		param($Windows)
		foreach ($window in @($Windows)) {
			$placed = $script:PlacedRects[[string]$window.Handle]
			if ($placed) {
				[PSCustomObject]@{
					Handle      = $window.Handle
					Title       = $window.Title
					ProcessName = $window.ProcessName
					Left = $placed.X; Top = $placed.Y; Width = $placed.Width; Height = $placed.Height
				}
			}
			else {
				$window
			}
		}
	}
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
		# The convergence rounds settle before each re-check; no test waits for real.
		Mock Start-Sleep { }

		# Placement is delegated to Resize-Windows in target-bounds mode; mock it, remember the
		# bounds it was asked for (see $script:AsPlaced) and report a successful resize so
		# Center-Windows counts the window as centered.
		$script:PlacedRects = @{}
		Mock Resize-Windows {
			$script:PlacedRects[[string]$WindowHandle] = @{ X = $TargetX; Y = $TargetY; Width = $TargetWidth; Height = $TargetHeight }
			$script:LastResizeWindowsResult = [PSCustomObject]@{
				ResizedCount  = 1
				SkippedCount  = 0
				FailedWindows = @()
			}
		}
		# Every placement is verified through Wait-WindowRect (real GetWindowRect is unavailable
		# here); report the requested bounds as verified unless a test overrides this.
		Mock Wait-WindowRect {
			[PSCustomObject]@{
				Verified = $true; X = $ExpectedX; Y = $ExpectedY
				Width = $ExpectedWidth; Height = $ExpectedHeight; ElapsedMs = 0
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
				& $script:AsPlaced @([PSCustomObject]@{
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
				& $script:AsPlaced @([PSCustomObject]@{
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

	Context "placement verification" {
		BeforeEach {
			Mock Get-MonitorInfo {
				@([PSCustomObject]@{
						DeviceName = '\\.\DISPLAY1'
						Left = 0; Top = 0; Right = 1920; Bottom = 1080
						Width = 1920; Height = 1080
						WorkAreaLeft = 0; WorkAreaTop = 0; WorkAreaRight = 1920; WorkAreaBottom = 1040
						WorkAreaWidth = 1920; WorkAreaHeight = 1040
						IsPrimary  = $true
					})
			}
			Mock Get-WindowDisplayName { 'Drifter' }
			Mock Test-LogVerbose { $false }
			Mock Write-LogSuccess { }
			Mock Write-LogWarning { }
			Mock Write-LogList { }
			Mock Get-CachedWindows {
				& $script:AsPlaced @([PSCustomObject]@{
						Handle      = [IntPtr]3
						Title       = 'Drifting Window'
						ProcessName = 'firefox'
						Left = 100; Top = 100; Width = 800; Height = 600
					})
			}
		}

		It "re-applies the placement once when the window does not hold the centered bounds" {
			$script:checks = 0
			Mock Wait-WindowRect {
				$script:checks++
				if ($script:checks -eq 1) {
					[PSCustomObject]@{ Verified = $false; X = 100; Y = 100; Width = 800; Height = 600; ElapsedMs = 150 }
				}
				else {
					[PSCustomObject]@{ Verified = $true; X = $ExpectedX; Y = $ExpectedY; Width = $ExpectedWidth; Height = $ExpectedHeight; ElapsedMs = 0 }
				}
			}

			Center-Windows -ProcessName "firefox"

			Should -Invoke Resize-Windows -Times 2 -Exactly
			Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -match 'Centered 1 window' }
			Should -Invoke Write-LogWarning -Times 0
		}

		It "reports a window that will not stay centered instead of counting it" {
			# Something keeps pulling the window back after every placement, and the live list
			# keeps showing it where it was pulled back to.
			Mock Wait-WindowRect {
				[PSCustomObject]@{ Verified = $false; X = 100; Y = 100; Width = 800; Height = 600; ElapsedMs = 150 }
			}
			Mock Get-CachedWindows {
				@([PSCustomObject]@{
						Handle      = [IntPtr]3
						Title       = 'Drifting Window'
						ProcessName = 'firefox'
						Left = 100; Top = 100; Width = 800; Height = 600
					})
			}

			Center-Windows -ProcessName "firefox"

			# Two attempts in the pass and two in each of the two re-centering rounds; the final
			# round only checks.
			Should -Invoke Resize-Windows -Times 6 -Exactly
			Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -match 'Centered 0 window' }
			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'could not be centered' }
			Should -Invoke Write-LogList -Times 1 -ParameterFilter { @($Items) -contains 'Drifter' }
		}
	}

	Context "convergence rounds" {
		BeforeEach {
			# One 1920x1040 work area: the defaults give the centered bounds (576, 260) [768x520].
			$script:primaryMonitor = [PSCustomObject]@{
				DeviceName = '\\.\DISPLAY1'
				Left = 0; Top = 0; Right = 1920; Bottom = 1080
				Width = 1920; Height = 1080
				WorkAreaLeft = 0; WorkAreaTop = 0; WorkAreaRight = 1920; WorkAreaBottom = 1040
				WorkAreaWidth = 1920; WorkAreaHeight = 1040
				IsPrimary  = $true
			}
			Mock Get-MonitorInfo { @($script:primaryMonitor) }
			Mock Get-WindowDisplayName { $Title }
			Mock Test-LogVerbose { $false }
			Mock Write-LogSuccess { }
			Mock Write-LogWarning { }
			Mock Write-LogList { }

			$script:enumerations = 0
			$script:notes = [PSCustomObject]@{ Handle = [IntPtr]10; Title = 'Notes'; ProcessName = 'Obsidian'; Left = 100; Top = 100; Width = 800; Height = 600 }
			$script:editor = [PSCustomObject]@{ Handle = [IntPtr]11; Title = 'Editor'; ProcessName = 'Code'; Left = 200; Top = 200; Width = 900; Height = 700 }
			# Where something else puts Notes after it was centered (a remembered zone, or the
			# app's own saved bounds).
			$script:drifted = [PSCustomObject]@{ Handle = [IntPtr]10; Title = 'Notes'; ProcessName = 'Obsidian'; Left = 0; Top = 0; Width = 960; Height = 1040 }
		}

		It "re-centers a window that moves after its placement was verified" {
			# The first re-check finds Notes moved; after that it stays where it is put.
			Mock Get-CachedWindows {
				$script:enumerations++
				if ($script:enumerations -eq 2) {
					@($script:drifted) + @(& $script:AsPlaced @($script:editor))
				}
				else {
					& $script:AsPlaced @($script:notes, $script:editor)
				}
			}

			Center-Windows

			Should -Invoke Resize-Windows -Times 2 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]10 }
			Should -Invoke Resize-Windows -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]11 }
			Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -match 'Centered 2 window' }
			Should -Invoke Write-LogWarning -Times 0
		}

		It "stops at the first round that finds every window holding its bounds" {
			Mock Get-CachedWindows { & $script:AsPlaced @($script:notes, $script:editor) }

			Center-Windows

			Should -Invoke Start-Sleep -Times 1 -Exactly
			Should -Invoke Resize-Windows -Times 2 -Exactly
		}

		It "re-centers a window at most twice and reports it when it keeps moving away" {
			# Every placement verifies, but every fresh enumeration shows Notes moved again.
			Mock Get-CachedWindows {
				$script:enumerations++
				if ($script:enumerations -eq 1) {
					@($script:notes, $script:editor)
				}
				else {
					@($script:drifted) + @(& $script:AsPlaced @($script:editor))
				}
			}

			Center-Windows

			# The pass, then re-centering rounds 1 and 2; round 3 only checks.
			Should -Invoke Resize-Windows -Times 3 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]10 }
			Should -Invoke Start-Sleep -Times 3 -Exactly
			Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -match 'Centered 1 window' }
			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match 'could not be centered' }
			Should -Invoke Write-LogList -Times 1 -ParameterFilter { @($Items) -contains 'Notes' }
		}

		It "brings a drifted window back to the bounds it was centered on, not to the monitor it drifted to" {
			$script:secondaryMonitor = [PSCustomObject]@{
				DeviceName = '\\.\DISPLAY2'
				Left = 1920; Top = 0; Right = 3840; Bottom = 1080
				Width = 1920; Height = 1080
				WorkAreaLeft = 1920; WorkAreaTop = 0; WorkAreaRight = 3840; WorkAreaBottom = 1040
				WorkAreaWidth = 1920; WorkAreaHeight = 1040
				IsPrimary  = $false
			}
			Mock Get-MonitorInfo { @($script:primaryMonitor, $script:secondaryMonitor) }
			$script:onSecondary = [PSCustomObject]@{ Handle = [IntPtr]10; Title = 'Notes'; ProcessName = 'Obsidian'; Left = 2200; Top = 100; Width = 800; Height = 600 }
			Mock Get-CachedWindows {
				$script:enumerations++
				if ($script:enumerations -eq 2) { @($script:onSecondary) } else { & $script:AsPlaced @($script:notes) }
			}

			Center-Windows

			Should -Invoke Resize-Windows -Times 2 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]10 -and $TargetX -eq 576 -and $TargetY -eq 260 }
			Should -Invoke Resize-Windows -Times 0 -Exactly -ParameterFilter { $TargetX -ge 1920 }
		}

		It "centers a window that was missing from the first enumeration" {
			# Editor had no title yet while it loaded, so the pass never saw it.
			Mock Get-CachedWindows {
				$script:enumerations++
				if ($script:enumerations -eq 1) { & $script:AsPlaced @($script:notes) } else { & $script:AsPlaced @($script:notes, $script:editor) }
			}

			Center-Windows

			Should -Invoke Resize-Windows -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]11 -and $TargetX -eq 576 }
			Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -match 'Centered 2 window' }
		}

		It "counts a window as centered when it settles on its bounds after its own verification gave up" {
			Mock Wait-WindowRect {
				[PSCustomObject]@{ Verified = $false; X = 100; Y = 100; Width = 800; Height = 600; ElapsedMs = 150 }
			}
			Mock Get-CachedWindows { & $script:AsPlaced @($script:notes) }

			Center-Windows

			# Two attempts in the pass; the first round then sees it holding its bounds.
			Should -Invoke Resize-Windows -Times 2 -Exactly
			Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -match 'Centered 1 window' }
			Should -Invoke Write-LogWarning -Times 0
		}
	}
}
