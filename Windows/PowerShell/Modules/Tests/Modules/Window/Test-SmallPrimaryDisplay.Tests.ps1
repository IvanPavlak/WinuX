#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Test-SmallPrimaryDisplay.ps1"
}

Describe "Test-SmallPrimaryDisplay" {
	BeforeEach {
		Mock Write-Host { }
		# The ultrawide is the "not small" baseline; individual cases override it.
		Mock Get-MonitorInfo { @([PSCustomObject]@{ IsPrimary = $true; Width = 3440; Height = 1440 }) }
	}

	It "reports a laptop-class primary display as small" {
		Mock Get-MonitorInfo { @([PSCustomObject]@{ IsPrimary = $true; Width = 1920; Height = 1080 }) }

		Test-SmallPrimaryDisplay | Should -BeTrue
	}

	It "treats the threshold width itself as small" {
		Mock Get-MonitorInfo { @([PSCustomObject]@{ IsPrimary = $true; Width = 3000; Height = 2000 }) }

		Test-SmallPrimaryDisplay | Should -BeTrue
	}

	It "reports a wide primary display as not small" {
		Test-SmallPrimaryDisplay | Should -BeFalse
	}

	It "measures the primary monitor, not the first one enumerated" {
		# The window lands on the primary display, so that is the one whose size decides.
		Mock Get-MonitorInfo {
			@(
				[PSCustomObject]@{ IsPrimary = $false; Width = 1920; Height = 1080 }
				[PSCustomObject]@{ IsPrimary = $true; Width = 3440; Height = 1440 }
			)
		}

		Test-SmallPrimaryDisplay | Should -BeFalse
	}

	It "falls back to the first monitor when none reports itself primary" {
		Mock Get-MonitorInfo {
			@(
				[PSCustomObject]@{ IsPrimary = $false; Width = 1920; Height = 1080 }
				[PSCustomObject]@{ IsPrimary = $false; Width = 3440; Height = 1440 }
			)
		}

		Test-SmallPrimaryDisplay | Should -BeTrue
	}

	It "reports not small when no monitors are detected" {
		# Never assume small: an unknown display must not silently change how windows are sized.
		Mock Get-MonitorInfo { @() }

		Test-SmallPrimaryDisplay | Should -BeFalse
	}

	It "uses a supplied monitor snapshot instead of querying" {
		Test-SmallPrimaryDisplay -MonitorInfo @([PSCustomObject]@{ IsPrimary = $true; Width = 1920; Height = 1080 }) |
			Should -BeTrue

		Should -Invoke Get-MonitorInfo -Times 0 -Exactly
	}

	It "honours a custom MaxWidthPx" {
		Mock Get-MonitorInfo { @([PSCustomObject]@{ IsPrimary = $true; Width = 2560; Height = 1440 }) }

		Test-SmallPrimaryDisplay | Should -BeTrue
		Test-SmallPrimaryDisplay -MaxWidthPx 2000 | Should -BeFalse
	}
}
