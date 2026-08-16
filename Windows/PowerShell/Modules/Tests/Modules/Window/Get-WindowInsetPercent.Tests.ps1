#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-WindowInsetPercent.ps1"

	# Every case rewrites the real session configuration, so put it back afterwards.
	$script:OriginalConfiguration = $global:Configuration
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Get-WindowInsetPercent" {
	BeforeEach {
		$global:Configuration = @{}
	}

	Context "built-in fallback" {
		It "returns 0.05 when no configuration is loaded at all" {
			$global:Configuration = $null

			Get-WindowInsetPercent | Should -Be 0.05
		}

		It "returns 0.05 when SnapInsetPercent is not set" {
			Get-WindowInsetPercent | Should -Be 0.05
		}

		It "returns a double" {
			Get-WindowInsetPercent | Should -BeOfType [double]
		}
	}

	Context "configured value" {
		It "returns the configured inset" {
			$global:Configuration = @{ SnapInsetPercent = 0.1 }

			Get-WindowInsetPercent | Should -Be 0.1
		}

		It "accepts zero (no inset)" {
			$global:Configuration = @{ SnapInsetPercent = 0.0 }

			Get-WindowInsetPercent | Should -Be 0.0
		}

		It "accepts the 0.49 ceiling" {
			$global:Configuration = @{ SnapInsetPercent = 0.49 }

			Get-WindowInsetPercent | Should -Be 0.49
		}

		It "accepts a numeric string" {
			$global:Configuration = @{ SnapInsetPercent = "0.08" }

			Get-WindowInsetPercent | Should -Be 0.08
		}
	}

	Context "invalid values fall back instead of throwing" {
		# Every consuming parameter declares [ValidateRange(0.0, 0.49)], so an out-of-range value
		# returned here would throw mid-loop during a workspace open. A config typo must not do that.
		It "falls back for <Label>" -ForEach @(
			@{ Label = "an inset above the ceiling"; Value = 0.9 }
			@{ Label = "a full-width inset"; Value = 0.5 }
			@{ Label = "a negative inset"; Value = -0.1 }
			@{ Label = "non-numeric text"; Value = "abc" }
			# The next three all cast to a perfectly valid 0.0 - PowerShell reads an empty
			# string as zero rather than failing - so each needs its own guard, or a blanked-out
			# config value would silently disable the inset instead of restoring the default.
			@{ Label = "an empty string"; Value = "" }
			@{ Label = "a whitespace string"; Value = "   " }
			@{ Label = "a boolean"; Value = $false }
		) {
			$global:Configuration = @{ SnapInsetPercent = $Value }

			Get-WindowInsetPercent | Should -Be 0.05
		}
	}
}
