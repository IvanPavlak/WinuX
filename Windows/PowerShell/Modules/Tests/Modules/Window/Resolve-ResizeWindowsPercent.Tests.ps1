#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	# The real row resolver, not a mock: which row a given display picks is part of the
	# behavior under test here.
	. "$FunctionsPath\Resolve-DisplayAwareProfile.ps1"
	. "$FunctionsPath\Resolve-ResizeWindowsPercent.ps1"

	# Stubbed so Mock can attach in a dot-sourced unit; both have their own suites.
	function Get-LayoutMachineType { param([object[]]$MonitorInfo) }
	function Test-SmallPrimaryDisplay { param([object[]]$MonitorInfo, [int]$MaxWidthPx) }

	# Every case rewrites the real session configuration, so put it back afterwards.
	$script:OriginalConfiguration = $global:Configuration
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Resolve-ResizeWindowsPercent" {
	BeforeEach {
		Mock Get-LayoutMachineType { 'Laptop' }
		Mock Test-SmallPrimaryDisplay { $false }
		$global:Configuration = @{}
	}

	Context "built-in fallback" {
		It "returns 70 when no configuration is loaded at all" {
			$global:Configuration = $null

			Resolve-ResizeWindowsPercent | Should -Be 70
		}

		It "returns 70 when the section is absent" {
			Resolve-ResizeWindowsPercent | Should -Be 70
		}

		It "returns 70 when the section is not a hashtable" {
			$global:Configuration = @{ ResizeWindowsPercent = 80 }

			Resolve-ResizeWindowsPercent | Should -Be 70
		}

		It "returns 70 when no row matched" {
			$global:Configuration = @{ ResizeWindowsPercent = @{ PC = 60 } }

			Resolve-ResizeWindowsPercent | Should -Be 70
		}
	}

	Context "row resolution" {
		BeforeEach {
			$global:Configuration = @{
				ResizeWindowsPercent = @{
					Default      = 70
					Laptop       = 65
					SmallDisplay = 80
				}
			}
		}

		It "returns the SmallDisplay row on a laptop-class panel" {
			Mock Test-SmallPrimaryDisplay { $true }

			Resolve-ResizeWindowsPercent | Should -Be 80
		}

		It "returns the machine type row once docked to a large display" {
			Resolve-ResizeWindowsPercent | Should -Be 65
		}

		It "returns the Default row when the machine type has none" {
			Mock Get-LayoutMachineType { 'Work' }

			Resolve-ResizeWindowsPercent | Should -Be 70
		}

		It "returns an int" {
			Resolve-ResizeWindowsPercent | Should -BeOfType [int]
		}

		It "forwards a supplied monitor snapshot" {
			$monitors = @([PSCustomObject]@{ IsPrimary = $true; Width = 1920; Height = 1080 })

			$null = Resolve-ResizeWindowsPercent -MonitorInfo $monitors

			Should -Invoke Test-SmallPrimaryDisplay -Times 1 -Exactly -ParameterFilter { $MonitorInfo.Count -eq 1 }
		}
	}

	Context "invalid values fall back instead of throwing" {
		# Resize-Windows declares [ValidateRange(10, 500)] on -Percent, so an out-of-range value
		# resolved here would throw mid-loop during a workspace open. A config typo must not do that.
		It "falls back for <Label>" -ForEach @(
			@{ Label = "a percentage below the range"; Value = 5 }
			@{ Label = "a percentage above the range"; Value = 700 }
			@{ Label = "zero"; Value = 0 }
			@{ Label = "a negative percentage"; Value = -20 }
			@{ Label = "non-numeric text"; Value = "abc" }
			@{ Label = "an empty string"; Value = "" }
			@{ Label = "a whitespace string"; Value = "   " }
		) {
			$global:Configuration = @{ ResizeWindowsPercent = @{ Default = $Value } }

			Resolve-ResizeWindowsPercent | Should -Be 70
		}

		It "accepts a numeric string" {
			$global:Configuration = @{ ResizeWindowsPercent = @{ Default = "85" } }

			Resolve-ResizeWindowsPercent | Should -Be 85
		}

		It "rounds a fractional percentage" {
			$global:Configuration = @{ ResizeWindowsPercent = @{ Default = 72.6 } }

			Resolve-ResizeWindowsPercent | Should -Be 73
		}
	}
}
