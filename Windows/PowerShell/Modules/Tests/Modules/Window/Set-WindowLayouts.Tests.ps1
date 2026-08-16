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
}
