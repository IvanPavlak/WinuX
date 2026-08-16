#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Resolve-CenterTerminalSizing.ps1"

	# Stubbed so Mock can attach in a dot-sourced unit; the row resolver has its own suite.
	function Resolve-DisplayAwareProfile { param([hashtable]$Section, [object[]]$MonitorInfo) }
}

Describe "Resolve-CenterTerminalSizing" {
	BeforeEach {
		Mock Resolve-DisplayAwareProfile { $null }
	}

	Context "legacy flat shape" {
		It "returns a flat section unchanged" {
			$flat = @{
				TargetWidthPx    = 1376
				TargetHeightPx   = 700
				MinWidthPercent  = 25
				MaxWidthPercent  = 72
				MinHeightPercent = 35
				MaxHeightPercent = 75
			}

			$result = Resolve-CenterTerminalSizing -Section $flat

			$result.TargetWidthPx | Should -Be 1376
			$result.MaxHeightPercent | Should -Be 75
			Should -Invoke Resolve-DisplayAwareProfile -Times 0 -Exactly
		}

		It "prefers the flat values in the hybrid shape a merged override produces" {
			# Configuration.local.psd1 deep-merges over the base, so a user who kept the old flat
			# override on top of a keyed base ends up with both in one hashtable. The flat keys
			# are the ones they actually edited, so those win.
			$hybrid = @{
				TargetWidthPx    = 1200
				TargetHeightPx   = 650
				MinWidthPercent  = 25
				MaxWidthPercent  = 72
				MinHeightPercent = 35
				MaxHeightPercent = 75
				Default          = @{ TargetWidthPx = 1376; TargetHeightPx = 700 }
			}

			$result = Resolve-CenterTerminalSizing -Section $hybrid

			$result.TargetWidthPx | Should -Be 1200
			Should -Invoke Resolve-DisplayAwareProfile -Times 0 -Exactly
		}
	}

	Context "keyed shape" {
		It "delegates row resolution and returns the resolved block" {
			Mock Resolve-DisplayAwareProfile { @{ TargetWidthPx = 1100; TargetHeightPx = 620 } }

			$result = Resolve-CenterTerminalSizing -Section @{ Default = @{ TargetWidthPx = 1376 } }

			$result.TargetWidthPx | Should -Be 1100
			Should -Invoke Resolve-DisplayAwareProfile -Times 1 -Exactly
		}

		It "forwards a supplied monitor snapshot to the row resolver" {
			$monitors = @([PSCustomObject]@{ IsPrimary = $true; Width = 1920; Height = 1080 })
			Mock Resolve-DisplayAwareProfile { @{ TargetWidthPx = 1376 } }

			$null = Resolve-CenterTerminalSizing -Section @{ Default = @{ TargetWidthPx = 1376 } } -MonitorInfo $monitors

			Should -Invoke Resolve-DisplayAwareProfile -Times 1 -Exactly -ParameterFilter { $MonitorInfo.Count -eq 1 }
		}

		It "rejects a row that is not a sizing block" {
			# Better to fall back to Center-Windows' own defaults than hand junk to
			# Resolve-CenteredWindowPercent, whose parameters are all mandatory ints.
			Mock Resolve-DisplayAwareProfile { 'not-a-sizing-block' }

			Resolve-CenterTerminalSizing -Section @{ Default = 'oops' } | Should -BeNullOrEmpty
		}

		It "rejects a hashtable row missing TargetWidthPx" {
			Mock Resolve-DisplayAwareProfile { @{ MinWidthPercent = 25 } }

			Resolve-CenterTerminalSizing -Section @{ Default = @{ MinWidthPercent = 25 } } | Should -BeNullOrEmpty
		}

		It "returns null when no row matched" {
			Resolve-CenterTerminalSizing -Section @{ PC = @{ TargetWidthPx = 1376 } } | Should -BeNullOrEmpty
		}
	}

	Context "absent section" {
		It "returns null for an empty section" {
			Resolve-CenterTerminalSizing -Section @{} | Should -BeNullOrEmpty
		}

		It "returns null when no section is supplied" {
			Resolve-CenterTerminalSizing | Should -BeNullOrEmpty
		}
	}
}
