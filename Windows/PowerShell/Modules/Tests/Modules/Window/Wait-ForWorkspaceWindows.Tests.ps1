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
				param($desktopNumber, $entries)
				$script:readyFired += [PSCustomObject]@{ Desktop = $desktopNumber; Count = @($entries).Count; Handle = @($entries)[0].Window.Handle; Entry = @($entries)[0].LayoutEntry }
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
		}

		It "keeps the per-entry OnWindowStable callback alongside the desktop callback" {
			$script:stableFired = 0
			$result = Wait-ForWorkspaceWindows -LayoutConfig $script:layout -TimeoutSeconds 10 -MinimumStableDurationSeconds 0 -PollIntervalSeconds 0.05 -OnWindowStable { $script:stableFired++ } -OnDesktopReady $script:onDesktopReady

			$result.Success | Should -BeTrue
			$script:stableFired | Should -Be 2
			$script:readyFired.Count | Should -Be 1
		}
	}
}
