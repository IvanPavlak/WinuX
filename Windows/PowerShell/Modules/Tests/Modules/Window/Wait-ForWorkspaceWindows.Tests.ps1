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
}
