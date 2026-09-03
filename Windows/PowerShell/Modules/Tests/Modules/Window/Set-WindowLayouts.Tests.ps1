#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Set-WindowLayouts.ps1"

	# The pre-snap inset source, stubbed so Mock can attach in a dot-sourced unit and so these
	# cases never read the live session configuration. It has its own suite.
	function Get-WindowInsetPercent { }
}

Describe "Set-WindowLayouts" {
	BeforeEach {
		Mock Get-WindowInsetPercent { 0.05 }
		Mock Initialize-PositionedWindowTracking { }
		Mock Test-Path { $false }
		Mock Write-Error { }
		Mock Resolve-LayoutTokens { param([hashtable]$LayoutEntry) $LayoutEntry }
	}

	It "returns when ConfigPath does not exist" {
		Set-WindowLayouts -ConfigPath "C:\\Missing\\layout.psd1"

		Should -Invoke Initialize-PositionedWindowTracking -Times 1
		Should -Invoke Test-Path -Times 1
		Should -Invoke Write-Error -Times 1
	}

	Context "SkipExistingWindows (alongside eligibility)" {
		# In alongside mode only the windows THIS open created may be laid out. Ineligible
		# candidates are dropped before any entry can claim one, so an entry left with nothing
		# reports "Not Found" - a countable shortfall - instead of silently placing nothing and
		# leaving the caller to believe the layout was complete.
		#
		# The entries below carry no Zone and no X/Y/Width/Height, so the positioning branch is
		# skipped entirely and the result status is all these tests need to observe.
		BeforeEach {
			Mock Test-LogVerbose { $false }
			Mock Write-LogDebug { }
			Mock Clear-WindowCache { }
			Mock Start-Sleep { }
		}

		BeforeAll {
			$script:browserEntry = @(@{ ProcessName = 'chrome' })
		}

		It "reports Not Found when every candidate window existed before the workspace opened" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Handle = [IntPtr]0xA1001; Title = 'New Tab - Google Chrome'; ProcessName = 'chrome' })
			}

			$existing = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$existing.Add([IntPtr]0xA1001)

			$results = @(Set-WindowLayouts -LayoutConfig $browserEntry -SkipExistingWindows -ExistingWindowHandles $existing)

			$results.Count | Should -Be 1
			$results[0].Status | Should -Be 'Not Found'
		}

		It "configures a window that this open created" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Handle = [IntPtr]0xA1002; Title = 'New Tab - Google Chrome'; ProcessName = 'chrome'; ProcessId = 4242 })
			}

			$existing = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$existing.Add([IntPtr]0xA1001)

			$results = @(Set-WindowLayouts -LayoutConfig $browserEntry -SkipExistingWindows -ExistingWindowHandles $existing)

			$results.Count | Should -Be 1
			$results[0].Status | Should -Be 'Configured'
		}

		It "counts a pre-existing window normally when SkipExistingWindows is not set" {
			# Control: the exclusion is alongside-only. A normal open legitimately re-uses
			# windows that were already on screen.
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Handle = [IntPtr]0xA1001; Title = 'New Tab - Google Chrome'; ProcessName = 'chrome'; ProcessId = 4242 })
			}

			$existing = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$existing.Add([IntPtr]0xA1001)

			$results = @(Set-WindowLayouts -LayoutConfig $browserEntry -ExistingWindowHandles $existing)

			$results.Count | Should -Be 1
			$results[0].Status | Should -Be 'Configured'
		}

		It "leaves an eligible window for a later duplicate entry instead of losing it to an earlier one" {
			# Two identical entries, two candidate windows, one of them pre-existing. The
			# ineligible window must not be claimed-then-skipped by the first entry: that
			# consumed the entry, produced no result, and left the handle unclaimed for the
			# second entry to lose itself on in exactly the same way.
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]0xA2001; Title = 'New Tab - Google Chrome'; ProcessName = 'chrome'; ProcessId = 4242 }
					[PSCustomObject]@{ Handle = [IntPtr]0xA2002; Title = 'New Tab - Google Chrome'; ProcessName = 'chrome'; ProcessId = 4243 }
				)
			}

			$existing = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$existing.Add([IntPtr]0xA2001)

			$duplicateEntries = @(@{ ProcessName = 'chrome' }, @{ ProcessName = 'chrome' })
			$results = @(Set-WindowLayouts -LayoutConfig $duplicateEntries -SkipExistingWindows -ExistingWindowHandles $existing)

			$results.Count | Should -Be 2
			@($results | Where-Object { $_.Status -eq 'Configured' }).Count | Should -Be 1
			@($results | Where-Object { $_.Status -eq 'Not Found' }).Count | Should -Be 1
		}
	}

	Context "ProtectedWindowHandles (plain-open preservation)" {
		# A preserved alongside workspace's window matches layout regexes exactly like any
		# other ("Browser" matches any browser window). It must be dropped from the candidate
		# list before claiming - a starved entry reports "Not Found" instead of stealing the
		# preserved window - and the per-window backstop must refuse one that arrives by a
		# path bypassing the filter.
		BeforeEach {
			Mock Test-LogVerbose { $false }
			Mock Write-LogDebug { }
			Mock Clear-WindowCache { }
			Mock Start-Sleep { }
		}

		BeforeAll {
			$script:protectedBrowserEntry = @(@{ ProcessName = 'chrome' })

			function New-ProtectedSet {
				param([int[]]$Handle)
				$set = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
				foreach ($item in $Handle) { [void]$set.Add([IntPtr]$item) }
				$set
			}
		}

		It "reports Not Found when the only candidate is a protected window" {
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Handle = [IntPtr]0xC1001; Title = 'YouTube - Google Chrome'; ProcessName = 'chrome'; ProcessId = 4242 })
			}

			$results = @(Set-WindowLayouts -LayoutConfig $protectedBrowserEntry -ProtectedWindowHandles (New-ProtectedSet 0xC1001))

			$results.Count | Should -Be 1
			$results[0].Status | Should -Be 'Not Found'
		}

		It "still claims an unprotected sibling next to a protected one" {
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]0xC1001; Title = 'YouTube - Google Chrome'; ProcessName = 'chrome'; ProcessId = 4242 }
					[PSCustomObject]@{ Handle = [IntPtr]0xC1002; Title = 'GitHub - Google Chrome'; ProcessName = 'chrome'; ProcessId = 4243 }
				)
			}

			$results = @(Set-WindowLayouts -LayoutConfig $protectedBrowserEntry -ProtectedWindowHandles (New-ProtectedSet 0xC1001))

			$results.Count | Should -Be 1
			$results[0].Status | Should -Be 'Configured'
			$results[0].Handle | Should -Be ([IntPtr]0xC1002)
		}

		It "never claims a protected window recovered by the wait-phase handle fallback" {
			# ExpectedWindowState's handle-recovery fallback resurrects windows the title search
			# missed - the exclusion (filter first, move-loop backstop behind it) must refuse a
			# protected window arriving by that route too.
			Mock Get-WindowHandle {
				param($ProcessName, $WindowTitle)
				if ($WindowTitle) { return $null }
				@([PSCustomObject]@{ Handle = [IntPtr]0xC1001; Title = 'Drifted Title'; ProcessName = 'chrome'; ProcessId = 4242 })
			}
			$expectedState = @{ ([IntPtr]0xC1001) = [PSCustomObject]@{ Title = 'YouTube - Google Chrome' } }
			$titleEntry = @(@{ ProcessName = 'chrome'; WindowTitle = 'YouTube.*' })

			$results = @(Set-WindowLayouts -LayoutConfig $titleEntry -ExpectedWindowState $expectedState `
					-ProtectedWindowHandles (New-ProtectedSet 0xC1001))

			@($results | Where-Object { $_.Status -eq 'Configured' }).Count | Should -Be 0
		}
	}

	Context "SingleZone plumbing (zone-based positioning)" {
		# A single-zone layout (Zone = "Fullscreen" on the one-zone "Zero" grid) must reach
		# Add-PositionedWindow with -SingleZone so Snap-AllWindows places the window directly
		# instead of steering FancyZones' relative Win+Arrow, which has no neighbouring zone
		# to resolve to on a single-zone grid.
		BeforeEach {
			Mock Test-LogVerbose { $false }
			Mock Write-LogDebug { }
			Mock Clear-WindowCache { }
			Mock Start-Sleep { }
			Mock Get-MonitorSpecs {
				[PSCustomObject]@{
					Primary = [PSCustomObject]@{ X = 0; Y = 0; WorkX = 0; WorkY = 0; WorkWidth = 2000; WorkHeight = 1000 }
				}
			}
			Mock Move-WindowToVirtualDesktop { $true }
			# The window is reported already at the adjusted (inset) bounds, so the
			# post-positioning verification passes and Add-PositionedWindow is reached.
			Mock Get-InsetWindowBounds {
				[PSCustomObject]@{ AdjustedX = 100; AdjustedY = 50; AdjustedWidth = 1800; AdjustedHeight = 900; ZoneCenterX = 1000; ZoneCenterY = 500 }
			}
			Mock Resize-Windows { $script:LastResizeWindowsResult = [PSCustomObject]@{ ResizedCount = 1 } }
			Mock Add-PositionedWindow { }
			Mock Get-WindowHandle {
				@([PSCustomObject]@{
						Handle = [IntPtr]0xB1001; Title = 'Claude'; ProcessName = 'claude'; ProcessId = 4242
						Left = 100; Top = 50; Width = 1800; Height = 900
					})
			}

			$script:LastMoveWindowToVirtualDesktopResult = $null
		}

		BeforeAll {
			$script:fullscreenEntry = @(@{ ProcessName = 'claude'; DesktopNumber = 2; Zone = 'Fullscreen'; Monitor = 'Primary' })
			$script:zeroMonitorConfig = @{ Primary = @{ VirtualDesktopLayouts = @{ 2 = 'Zero' } } }
			$script:dummyMonitorInfo = @([PSCustomObject]@{ DeviceName = '\\.\DISPLAY1' })
		}

		It "tracks the window with -SingleZone when the resolved layout has one zone" {
			Mock Get-FancyZone {
				[PSCustomObject]@{ X = 0; Y = 0; Width = 2000; Height = 1000; ZoneIndex = 0; ZoneName = 'Fullscreen'; TotalZoneCount = 1 }
			}

			$null = Set-WindowLayouts -LayoutConfig $fullscreenEntry -MonitorInfo $dummyMonitorInfo -MonitorConfig $zeroMonitorConfig

			Should -Invoke Add-PositionedWindow -Times 1 -Exactly -ParameterFilter {
				$SingleZone -eq $true -and $DesktopNumber -eq 2 -and $ExpectedX -eq 0 -and $ExpectedWidth -eq 2000
			}
		}

		It "tracks the window without -SingleZone when the resolved layout has multiple zones" {
			Mock Get-FancyZone {
				[PSCustomObject]@{ X = 0; Y = 0; Width = 2000; Height = 1000; ZoneIndex = 0; ZoneName = 'Left'; TotalZoneCount = 2 }
			}

			$null = Set-WindowLayouts -LayoutConfig $fullscreenEntry -MonitorInfo $dummyMonitorInfo -MonitorConfig $zeroMonitorConfig

			Should -Invoke Add-PositionedWindow -Times 1 -Exactly -ParameterFilter { -not $SingleZone }
		}
	}

	Context "Per-desktop pipelining filters (CandidateWindowHandles, ExcludeWindowHandles, KeepPositionedWindows)" {
		# Same shape as the alongside-eligibility cases: no Zone and no coordinates, so the
		# positioning branch is skipped and the result rows are all that matters. A catch-all
		# entry matches BOTH windows of its process, which is exactly why these filters are
		# enforced on the candidate list rather than left to the title regex.
		BeforeEach {
			Mock Test-LogVerbose { $false }
			Mock Write-LogDebug { }
			Mock Clear-WindowCache { }
			Mock Start-Sleep { }
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]0xB1001; Title = 'Docs - Google Chrome'; ProcessName = 'chrome' }
					[PSCustomObject]@{ Handle = [IntPtr]0xB1002; Title = 'Mail - Google Chrome'; ProcessName = 'chrome' }
				)
			}
			$script:chromeEntry = @(@{ ProcessName = 'chrome' })
		}

		It "claims only the windows inside -CandidateWindowHandles" {
			$candidates = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$candidates.Add([IntPtr]0xB1002)

			$results = @(Set-WindowLayouts -LayoutConfig $script:chromeEntry -CandidateWindowHandles $candidates)

			$configured = @($results | Where-Object { $_.Status -eq 'Configured' })
			$configured.Count | Should -Be 1
			$configured[0].Handle | Should -Be ([IntPtr]0xB1002)
		}

		It "reports Not Found when no candidate window is eligible" {
			$candidates = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$candidates.Add([IntPtr]0xB1003)

			$results = @(Set-WindowLayouts -LayoutConfig $script:chromeEntry -CandidateWindowHandles $candidates)

			$results.Count | Should -Be 1
			$results[0].Status | Should -Be 'Not Found'
		}

		It "never claims a window in -ExcludeWindowHandles" {
			$excluded = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$excluded.Add([IntPtr]0xB1001)

			$results = @(Set-WindowLayouts -LayoutConfig $script:chromeEntry -ExcludeWindowHandles $excluded)

			$configured = @($results | Where-Object { $_.Status -eq 'Configured' })
			$configured.Count | Should -Be 1
			$configured[0].Handle | Should -Be ([IntPtr]0xB1002)
		}

		It "claims every match when neither filter is given" {
			$results = @(Set-WindowLayouts -LayoutConfig $script:chromeEntry)

			@($results | Where-Object { $_.Status -eq 'Configured' }).Count | Should -Be 2
		}

		It "counts duplicate keys over the whole layout while processing only the -DesktopNumbers entries" {
			# The same catch-all key on desktops 1 and 2: processing desktop 2 alone must still claim
			# exactly ONE window - a subset of one entry would have "applied the layout to all".
			$layout = @(
				@{ ProcessName = 'chrome'; DesktopNumber = 1 }
				@{ ProcessName = 'chrome'; DesktopNumber = 2 }
			)

			$results = @(Set-WindowLayouts -LayoutConfig $layout -DesktopNumbers 2)

			$results.Count | Should -Be 1
			$results[0].Status | Should -Be 'Configured'
			$results[0].DesktopNumber | Should -Be 2
			$results[0].EntryKey | Should -Be '2|||chrome|'
		}

		It "skips the entries named in -SkipEntryKeys and still counts them as duplicates" {
			$layout = @(
				@{ ProcessName = 'chrome'; DesktopNumber = 1 }
				@{ ProcessName = 'chrome'; DesktopNumber = 2 }
			)
			$placed = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$placed.Add([IntPtr]0xB1001)

			$results = @(Set-WindowLayouts -LayoutConfig $layout -SkipEntryKeys '2|||chrome|' -ExcludeWindowHandles $placed)

			# Only desktop 1's entry runs, as a duplicate-key entry, and claims the one unplaced window.
			$results.Count | Should -Be 1
			$results[0].DesktopNumber | Should -Be 1
			$results[0].Handle | Should -Be ([IntPtr]0xB1002)
		}

		It "puts the entry key on every result row, Not Found included" {
			$candidates = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$candidates.Add([IntPtr]0xB1003)

			$results = @(Set-WindowLayouts -LayoutConfig @(@{ ProcessName = 'chrome'; DesktopNumber = 3 }) -CandidateWindowHandles $candidates)

			$results[0].Status | Should -Be 'Not Found'
			$results[0].EntryKey | Should -Be '3|||chrome|'
		}

		It "leaves the positioned-window tracking alone with -KeepPositionedWindows" {
			$null = Set-WindowLayouts -LayoutConfig $script:chromeEntry -KeepPositionedWindows

			Should -Invoke Initialize-PositionedWindowTracking -Times 0 -Exactly
		}

		It "resets the positioned-window tracking by default" {
			$null = Set-WindowLayouts -LayoutConfig $script:chromeEntry

			Should -Invoke Initialize-PositionedWindowTracking -Times 1 -Exactly
		}
	}
}
