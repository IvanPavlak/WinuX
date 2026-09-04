#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Wait-ForWorkspaceWindows.ps1"
}

Describe "Wait-ForWorkspaceWindows" {
	BeforeEach {
		Mock Resolve-LayoutTokens { param([hashtable]$LayoutEntry) $LayoutEntry }
		Mock Clear-WindowCache { }
	}

	It "rejects empty layout input" {
		{ Wait-ForWorkspaceWindows -LayoutConfig @() } | Should -Throw
		Should -Invoke Clear-WindowCache -Times 0
	}

	Context "Stability floor and fail-fast" {
		BeforeEach {
			$script:stableAppWindow = [PSCustomObject]@{
				Handle      = [IntPtr]100
				Title       = "App Main Window"
				ProcessName = "App"
				Left        = 10
				Top         = 10
				Width       = 800
				Height      = 600
			}

			Mock Get-WindowHandle {
				if ($ProcessName -eq 'App') { @($script:stableAppWindow) } else { @() }
			}
		}

		It "returns success without an extra collective settle once windows are individually stable (CollectiveStabilitySeconds defaults to 0)" {
			$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

			$result = Wait-ForWorkspaceWindows `
				-LayoutConfig @(@{ ProcessName = 'App' }) `
				-TimeoutSeconds 10 `
				-MinimumStableDurationSeconds 0

			$stopwatch.Stop()

			$result.Success | Should -BeTrue
			$result.WindowStates.Count | Should -Be 1
			# Individual stability tracking already resets on any change - the old
			# sequential collective phase added a guaranteed +1s to every open.
			$stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 1.5
		}

		It "honors an explicit CollectiveStabilitySeconds settle when requested" {
			$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

			$result = Wait-ForWorkspaceWindows `
				-LayoutConfig @(@{ ProcessName = 'App' }) `
				-TimeoutSeconds 10 `
				-MinimumStableDurationSeconds 0 `
				-CollectiveStabilitySeconds 0.4

			$stopwatch.Stop()

			$result.Success | Should -BeTrue
			$stopwatch.Elapsed.TotalSeconds | Should -BeGreaterOrEqual 0.4
		}

		It "abandons an entry whose process never appears instead of burning the whole timeout" {
			Mock Get-Process { @([PSCustomObject]@{ ProcessName = 'pwsh' }) }

			$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

			$result = Wait-ForWorkspaceWindows `
				-LayoutConfig @(
					@{ ProcessName = 'App' }
					@{ ProcessName = 'GhostProcessNeverRuns' }
				) `
				-TimeoutSeconds 30 `
				-MinimumStableDurationSeconds 0 `
				-ProcessAbsentGraceSeconds 1

			$stopwatch.Stop()

			# The dead entry is abandoned after the grace period and the loop exits as soon
			# as everything else is stable - nowhere near the 30s timeout.
			$stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 10
			$result.Success | Should -BeFalse
			@($result.Abandoned) | Should -Contain 'GhostProcessNeverRuns'
			@($result.AbandonedEntries)[0].ProcessName | Should -Be 'GhostProcessNeverRuns'
			# The stable window's state snapshot is still returned for downstream fallbacks.
			$result.WindowStates.Count | Should -Be 1
		}

		It "never abandons an entry whose process is alive (only window/title still pending)" {
			Mock Get-Process { @([PSCustomObject]@{ ProcessName = 'SlowApp' }) }

			$result = Wait-ForWorkspaceWindows `
				-LayoutConfig @(@{ ProcessName = 'SlowApp' }) `
				-TimeoutSeconds 2 `
				-MinimumStableDurationSeconds 0 `
				-ProcessAbsentGraceSeconds 1

			# Times out (window never appears) but is NOT abandoned - the process exists,
			# so the window may still be coming.
			$result.Success | Should -BeFalse
			@($result.Abandoned).Count | Should -Be 0
		}
	}

	Context "Per-desktop readiness (-OnDesktopReady)" {
		BeforeEach {
			$script:appWindow = [PSCustomObject]@{ Handle = [IntPtr]100; Title = 'App Main Window'; ProcessName = 'App'; Left = 10; Top = 10; Width = 800; Height = 600 }
			$script:slowWindow = [PSCustomObject]@{ Handle = [IntPtr]200; Title = 'Slow Main Window'; ProcessName = 'Slow'; Left = 20; Top = 20; Width = 800; Height = 600 }
			$script:clock = [System.Diagnostics.Stopwatch]::StartNew()
			# The slow window appears after this many milliseconds; $null means right away.
			$script:slowAppearsAfterMs = 400
			# When set, the App window disappears from enumeration after this many milliseconds.
			$script:appVanishesAfterMs = $null

			Mock Get-WindowHandle {
				if ($ProcessName -eq 'App') {
					if ($null -ne $script:appVanishesAfterMs -and $script:clock.ElapsedMilliseconds -gt $script:appVanishesAfterMs) { return @() }
					return @($script:appWindow)
				}
				if ($ProcessName -eq 'Slow') {
					if ($null -eq $script:slowAppearsAfterMs -or $script:clock.ElapsedMilliseconds -gt $script:slowAppearsAfterMs) { return @($script:slowWindow) }
					return @()
				}
				@()
			}
			Mock Get-Process { @([PSCustomObject]@{ ProcessName = 'App' }, [PSCustomObject]@{ ProcessName = 'Slow' }) }

			$script:readyFired = @()
			$script:onDesktopReady = {
				param($desktopNumber, $entries, $stableHandles, $abandonedEntries)
				$script:readyFired += [PSCustomObject]@{ Desktop = $desktopNumber; Count = @($entries).Count; Handle = @($entries)[0].Window.Handle; Entry = @($entries)[0].LayoutEntry; StableHandles = @($stableHandles); Abandoned = @($abandonedEntries) }
			}
			$script:layout = @(
				@{ ProcessName = 'App'; DesktopNumber = 1 }
				@{ ProcessName = 'Slow'; DesktopNumber = 2 }
			)
		}

		It "fires once for a desktop whose entries are all stable while another desktop still loads" {
			$result = Wait-ForWorkspaceWindows -LayoutConfig $script:layout -TimeoutSeconds 10 -MinimumStableDurationSeconds 0 -PollIntervalSeconds 0.05 -OnDesktopReady $script:onDesktopReady

			$result.Success | Should -BeTrue
			$script:readyFired.Count | Should -Be 1
			$script:readyFired[0].Desktop | Should -Be 1
			$script:readyFired[0].Count | Should -Be 1
			$script:readyFired[0].Handle | Should -Be ([IntPtr]100)
			$script:readyFired[0].Entry.ProcessName | Should -Be 'App'
			# Every window stable in that poll comes along as the candidate set - here App alone,
			# since Slow had not appeared yet.
			@($script:readyFired[0].StableHandles) | Should -Be @([IntPtr]100)
			# Desktop 2 completed in the poll that completed the wait - never handed over.
			@($result.ReadyDesktops) | Should -Be @(1)
		}

		It "does not fire when every desktop completes in the same poll" {
			$script:slowAppearsAfterMs = $null

			$result = Wait-ForWorkspaceWindows -LayoutConfig $script:layout -TimeoutSeconds 10 -MinimumStableDurationSeconds 0 -PollIntervalSeconds 0.05 -OnDesktopReady $script:onDesktopReady

			$result.Success | Should -BeTrue
			$script:readyFired.Count | Should -Be 0
			@($result.ReadyDesktops).Count | Should -Be 0
		}

		It "treats a handed-over entry as ready for the rest of the wait, whatever its window does next" {
			# The caller moves and snaps the handed-over window, so it may look changed or even be
			# gone from a later enumeration; the wait must complete on the OTHER desktop alone.
			$script:appVanishesAfterMs = 150
			$script:slowAppearsAfterMs = 600

			$result = Wait-ForWorkspaceWindows -LayoutConfig $script:layout -TimeoutSeconds 3 -MinimumStableDurationSeconds 0 -PollIntervalSeconds 0.05 -OnDesktopReady $script:onDesktopReady

			$result.Success | Should -BeTrue
			$script:readyFired.Count | Should -Be 1
			$script:clock.Elapsed.TotalSeconds | Should -BeLessThan 2.5
		}

		It "lets an abandoned entry on the desktop count as done for the desktop's readiness" {
			$script:layout = @(
				@{ ProcessName = 'App'; DesktopNumber = 1 }
				@{ ProcessName = 'Ghost'; DesktopNumber = 1 }
				@{ ProcessName = 'Slow'; DesktopNumber = 2 }
			)
			$script:slowAppearsAfterMs = 1800

			$result = Wait-ForWorkspaceWindows -LayoutConfig $script:layout -TimeoutSeconds 6 -MinimumStableDurationSeconds 0 -PollIntervalSeconds 0.05 -ProcessAbsentGraceSeconds 1 -OnDesktopReady $script:onDesktopReady

			# Ghost is abandoned after the grace period; desktop 1 is then ready with App alone.
			$script:readyFired.Count | Should -Be 1
			$script:readyFired[0].Desktop | Should -Be 1
			$script:readyFired[0].Count | Should -Be 1
			@($result.Abandoned).Count | Should -Be 1
			# The abandoned entry travels as a layout entry: with the callback (fourth argument),
			# so the per-desktop layout pass skips its not-found ladder, and in the result.
			@($script:readyFired[0].Abandoned).Count | Should -Be 1
			@($script:readyFired[0].Abandoned)[0].ProcessName | Should -Be 'Ghost'
			@($result.AbandonedEntries).Count | Should -Be 1
			@($result.AbandonedEntries)[0].ProcessName | Should -Be 'Ghost'
		}

		It "keeps the per-entry OnWindowStable callback alongside the desktop callback" {
			$script:stableFired = 0
			$result = Wait-ForWorkspaceWindows -LayoutConfig $script:layout -TimeoutSeconds 10 -MinimumStableDurationSeconds 0 -PollIntervalSeconds 0.05 -OnWindowStable { $script:stableFired++ } -OnDesktopReady $script:onDesktopReady

			$result.Success | Should -BeTrue
			$script:stableFired | Should -Be 2
			$script:readyFired.Count | Should -Be 1
		}
	}

	Context "Stability credit and excluded windows" {
		# Two trims that leave the stability rules alone. A window that existed before the open
		# has nothing to stabilize (plain mode) or is another workspace's and never matches
		# (alongside, protected). Windows the launch actions created earn the floor as before.
		BeforeEach {
			$script:appWindow = [PSCustomObject]@{ Handle = [IntPtr]100; Title = 'App Main Window'; ProcessName = 'App'; Left = 10; Top = 10; Width = 800; Height = 600 }
			$script:extraAppWindows = @()
			Mock Get-WindowHandle {
				if ($ProcessName -eq 'App') { return @(@($script:appWindow) + @($script:extraAppWindows)) }
				@()
			}
			Mock Get-Process { @([PSCustomObject]@{ ProcessName = 'App' }) }
			$script:layout = @(@{ ProcessName = 'App'; DesktopNumber = 1 })
			$script:clock = [System.Diagnostics.Stopwatch]::StartNew()
		}

		It "counts a pre-existing window as stable on first sight instead of observing it for the stability floor" {
			$preExisting = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$preExisting.Add([IntPtr]100)

			$result = Wait-ForWorkspaceWindows -LayoutConfig $script:layout -TimeoutSeconds 5 -MinimumStableDurationSeconds 3 -PollIntervalSeconds 0.05 -PreExistingWindowHandles $preExisting

			$result.Success | Should -BeTrue
			$script:clock.Elapsed.TotalSeconds | Should -BeLessThan 2
			$result.WindowStates.ContainsKey([IntPtr]100) | Should -BeTrue
		}

		It "still observes a window outside the pre-existing set for the whole floor" {
			$preExisting = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$preExisting.Add([IntPtr]999)

			$result = Wait-ForWorkspaceWindows -LayoutConfig $script:layout -TimeoutSeconds 5 -MinimumStableDurationSeconds 1 -PollIntervalSeconds 0.05 -PreExistingWindowHandles $preExisting

			$result.Success | Should -BeTrue
			$script:clock.Elapsed.TotalSeconds | Should -BeGreaterOrEqual 0.9
		}

		It "gives a window the launch actions created no credit for the time it was visible before the wait started" {
			# An application's first window can be replaced seconds after launch (VS Code hands
			# its window from the launcher to the main process, same title and size); only the
			# floor catches that, so nothing but the pre-open capture earns credit.
			$result = Wait-ForWorkspaceWindows -LayoutConfig $script:layout -TimeoutSeconds 5 -MinimumStableDurationSeconds 1 -PollIntervalSeconds 0.05

			$result.Success | Should -BeTrue
			$script:clock.Elapsed.TotalSeconds | Should -BeGreaterOrEqual 0.9
		}

		It "never matches an excluded window, and abandons an entry only such windows match after the grace period" {
			$excluded = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$excluded.Add([IntPtr]100)

			$result = Wait-ForWorkspaceWindows -LayoutConfig $script:layout -TimeoutSeconds 10 -MinimumStableDurationSeconds 0 -PollIntervalSeconds 0.05 -ProcessAbsentGraceSeconds 1 -ExcludeWindowHandles $excluded

			$result.Success | Should -BeFalse
			@($result.Abandoned).Count | Should -Be 1
			@($result.AbandonedEntries)[0].ProcessName | Should -Be 'App'
			$result.WindowStates.ContainsKey([IntPtr]100) | Should -BeFalse
			# The grace period, not the timeout.
			$script:clock.Elapsed.TotalSeconds | Should -BeLessThan 5
		}

		It "matches the new window that appears next to an excluded one" {
			$excluded = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
			[void]$excluded.Add([IntPtr]100)
			$script:extraAppWindows = @([PSCustomObject]@{ Handle = [IntPtr]300; Title = 'App New Window'; ProcessName = 'App'; Left = 0; Top = 0; Width = 800; Height = 600 })
			$script:stableHandle = $null

			$result = Wait-ForWorkspaceWindows -LayoutConfig $script:layout -TimeoutSeconds 5 -MinimumStableDurationSeconds 0 -PollIntervalSeconds 0.05 -ExcludeWindowHandles $excluded -OnWindowStable { param($entry, $window) $script:stableHandle = $window.Handle }

			$result.Success | Should -BeTrue
			$script:stableHandle | Should -Be ([IntPtr]300)
		}
	}

	Context "Entry matching for the early move and the desktop hand-over" {
		# Get-WindowHandle matches process OR title. A title pattern that happens to match a
		# window of ANOTHER process ("\bSEUP\b" against "seup-ui - Visual Studio Code") must not
		# make that window the entry's match: the early move carried VS Code to the browser's
		# desktop after its own pass had placed it, and the open needed a second attempt.
		BeforeEach {
			$script:codeWindow = [PSCustomObject]@{ Handle = [IntPtr]300; Title = 'seup-ui - Visual Studio Code'; ProcessName = 'Code'; Left = 0; Top = 0; Width = 800; Height = 600 }
			$script:browserWindows = @()
			Mock Get-WindowHandle {
				# The OR match: the Code window matches the browser entry's title, browser windows
				# match its process.
				if ($ProcessName -match 'firefox') { return @(@($script:codeWindow) + @($script:browserWindows)) }
				if ($ProcessName -eq 'Code') { return @($script:codeWindow) }
				@()
			}
			Mock Get-Process { @([PSCustomObject]@{ ProcessName = 'firefox' }, [PSCustomObject]@{ ProcessName = 'Code' }) }
			$script:moved = @()
			$script:onStable = { param($entry, $window) $script:moved += [PSCustomObject]@{ Process = $entry.ProcessName; Handle = $window.Handle } }
			$script:readyFired = @()
			$script:onDesktopReady = { param($desktopNumber, $entries, $stableHandles, $abandoned) $script:readyFired += [PSCustomObject]@{ Desktop = $desktopNumber; Handles = @($stableHandles) } }
		}

		It "never matches an entry to a window of another process, whatever the title says" {
			$layout = @(@{ ProcessName = 'firefox'; WindowTitle = '.*\bSEUP\b.*'; DesktopNumber = 4 })

			$result = Wait-ForWorkspaceWindows -LayoutConfig $layout -TimeoutSeconds 1.5 -MinimumStableDurationSeconds 0 -PollIntervalSeconds 0.05 -ProcessAbsentGraceSeconds 0 -OnWindowStable $script:onStable

			$result.Success | Should -BeFalse
			$script:moved.Count | Should -Be 0
		}

		It "still matches a window of the entry's process by process alone while its title is loading" {
			$script:browserWindows = @([PSCustomObject]@{ Handle = [IntPtr]301; Title = 'Problem loading page - Mozilla Firefox'; ProcessName = 'firefox'; Left = 0; Top = 0; Width = 800; Height = 600 })
			$layout = @(@{ ProcessName = 'firefox'; WindowTitle = '.*Slack.*'; DesktopNumber = 5 })

			$result = Wait-ForWorkspaceWindows -LayoutConfig $layout -TimeoutSeconds 5 -MinimumStableDurationSeconds 0 -PollIntervalSeconds 0.05 -OnWindowStable $script:onStable

			$result.Success | Should -BeTrue
			$script:moved.Count | Should -Be 1
			$script:moved[0].Handle | Should -Be ([IntPtr]301)
		}

		It "hands a desktop over only when its titled entries match by title, not merely by process" {
			# Desktop 5: a titled browser entry stable on a browser window whose title does not
			# match it yet. Desktop 1: the Code entry. The Slow entry keeps the wait going.
			$script:browserWindows = @([PSCustomObject]@{ Handle = [IntPtr]301; Title = 'Problem loading page - Mozilla Firefox'; ProcessName = 'firefox'; Left = 0; Top = 0; Width = 800; Height = 600 })
			$script:clock = [System.Diagnostics.Stopwatch]::StartNew()
			Mock Get-WindowHandle {
				if ($ProcessName -match 'firefox') { return @(@($script:codeWindow) + @($script:browserWindows)) }
				if ($ProcessName -eq 'Code') { return @($script:codeWindow) }
				if ($ProcessName -eq 'Slow' -and $script:clock.ElapsedMilliseconds -gt 600) { return @([PSCustomObject]@{ Handle = [IntPtr]302; Title = 'Slow'; ProcessName = 'Slow'; Left = 0; Top = 0; Width = 800; Height = 600 }) }
				@()
			}
			Mock Get-Process { @([PSCustomObject]@{ ProcessName = 'firefox' }, [PSCustomObject]@{ ProcessName = 'Code' }, [PSCustomObject]@{ ProcessName = 'Slow' }) }
			$layout = @(
				@{ ProcessName = 'Code'; DesktopNumber = 1 }
				@{ ProcessName = 'firefox'; WindowTitle = '.*Slack.*'; DesktopNumber = 5 }
				@{ ProcessName = 'Slow'; DesktopNumber = 2 }
			)

			$result = Wait-ForWorkspaceWindows -LayoutConfig $layout -TimeoutSeconds 5 -MinimumStableDurationSeconds 0 -PollIntervalSeconds 0.05 -OnDesktopReady $script:onDesktopReady

			$result.Success | Should -BeTrue
			@($script:readyFired | Where-Object { $_.Desktop -eq 1 }).Count | Should -Be 1
			@($script:readyFired | Where-Object { $_.Desktop -eq 5 }).Count | Should -Be 0
			# The browser window is stable, so it is still a legitimate claim for the desktop-1 pass.
			@($script:readyFired[0].Handles) | Should -Contain ([IntPtr]301)
		}

		It "hands the desktop over once the titled entry's window carries the title" {
			$script:browserWindows = @([PSCustomObject]@{ Handle = [IntPtr]301; Title = 'futurama - Slack - Mozilla Firefox'; ProcessName = 'firefox'; Left = 0; Top = 0; Width = 800; Height = 600 })
			$script:clock = [System.Diagnostics.Stopwatch]::StartNew()
			Mock Get-WindowHandle {
				if ($ProcessName -match 'firefox') { return @(@($script:codeWindow) + @($script:browserWindows)) }
				if ($ProcessName -eq 'Slow' -and $script:clock.ElapsedMilliseconds -gt 600) { return @([PSCustomObject]@{ Handle = [IntPtr]302; Title = 'Slow'; ProcessName = 'Slow'; Left = 0; Top = 0; Width = 800; Height = 600 }) }
				@()
			}
			Mock Get-Process { @([PSCustomObject]@{ ProcessName = 'firefox' }, [PSCustomObject]@{ ProcessName = 'Slow' }) }
			$layout = @(
				@{ ProcessName = 'firefox'; WindowTitle = '.*Slack.*'; DesktopNumber = 5 }
				@{ ProcessName = 'Slow'; DesktopNumber = 2 }
			)

			$result = Wait-ForWorkspaceWindows -LayoutConfig $layout -TimeoutSeconds 5 -MinimumStableDurationSeconds 0 -PollIntervalSeconds 0.05 -OnDesktopReady $script:onDesktopReady

			$result.Success | Should -BeTrue
			@($script:readyFired | Where-Object { $_.Desktop -eq 5 }).Count | Should -Be 1
		}
	}
}
