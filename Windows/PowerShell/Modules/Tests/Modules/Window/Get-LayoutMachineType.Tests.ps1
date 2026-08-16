#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	# The real display measurement, not a mock: the small-display cases below drive it through
	# their Get-MonitorInfo mocks, exactly as the live code path does.
	. "$FunctionsPath\Test-SmallPrimaryDisplay.ps1"
	. "$FunctionsPath\Get-LayoutMachineType.ps1"
}

Describe "Get-LayoutMachineType" {
	BeforeEach {
		Mock Write-Host { }
		Mock DetermineMachineType { 'PC' }
		Mock Get-MonitorInfo { @([PSCustomObject]@{ IsPrimary = $true; Width = 3440; Height = 1440 }) }

		# The function reads its two keys through the unqualified $Configuration, which resolves to
		# this file's script scope - reset it per test so nothing leaks between cases.
		$script:Configuration = @{}
	}

	It "returns the detected machine type when nothing is configured" {
		Get-LayoutMachineType | Should -BeExactly 'PC'
	}

	It "returns the override layout set configured for the detected machine type" {
		$script:Configuration = @{ LayoutMachineTypeOverrides = @{ PC = 'Temp' } }

		Get-LayoutMachineType | Should -BeExactly 'Temp'
	}

	It "ignores an empty override entry" {
		$script:Configuration = @{ LayoutMachineTypeOverrides = @{ PC = '   ' } }

		Get-LayoutMachineType | Should -BeExactly 'PC'
	}

	It "ignores an override entry belonging to a different machine type" {
		$script:Configuration = @{ LayoutMachineTypeOverrides = @{ Laptop = 'Temp' } }

		Get-LayoutMachineType | Should -BeExactly 'PC'
	}

	It "trims the configured override value" {
		$script:Configuration = @{ LayoutMachineTypeOverrides = @{ PC = "  Temp`t" } }

		Get-LayoutMachineType | Should -BeExactly 'Temp'
	}

	It "prefers the override over the small-display machine type" {
		# The whole reason the override is resolved first: a temporary single screen is exactly the
		# case that would otherwise trigger the display-size rule and silently discard the choice.
		$script:Configuration = @{
			LayoutMachineTypeOverrides = @{ PC = 'Temp' }
			SmallDisplayMachineType    = 'Laptop'
		}
		Mock Get-MonitorInfo { @([PSCustomObject]@{ IsPrimary = $true; Width = 1920; Height = 1080 }) }

		Get-LayoutMachineType | Should -BeExactly 'Temp'
	}

	It "falls back to the small-display machine type on a laptop-class primary display" {
		$script:Configuration = @{ SmallDisplayMachineType = 'Laptop' }
		Mock Get-MonitorInfo { @([PSCustomObject]@{ IsPrimary = $true; Width = 1920; Height = 1080 }) }

		Get-LayoutMachineType | Should -BeExactly 'Laptop'
	}

	It "keeps the detected machine type on a wide primary display" {
		$script:Configuration = @{ SmallDisplayMachineType = 'Laptop' }

		Get-LayoutMachineType | Should -BeExactly 'PC'
	}

	It "measures the primary monitor, not the first one enumerated" {
		$script:Configuration = @{ SmallDisplayMachineType = 'Laptop' }
		Mock Get-MonitorInfo {
			@(
				[PSCustomObject]@{ IsPrimary = $false; Width = 1920; Height = 1080 }
				[PSCustomObject]@{ IsPrimary = $true; Width = 3440; Height = 1440 }
			)
		}

		Get-LayoutMachineType | Should -BeExactly 'PC'
	}

	It "does not query monitors when an override already answered" {
		$script:Configuration = @{
			LayoutMachineTypeOverrides = @{ PC = 'Temp' }
			SmallDisplayMachineType    = 'Laptop'
		}

		$null = Get-LayoutMachineType

		Should -Invoke Get-MonitorInfo -Times 0 -Exactly
	}

	It "does not query monitors when no small-display machine type is configured" {
		$script:Configuration = @{ SmallDisplayMachineType = '' }

		$null = Get-LayoutMachineType

		Should -Invoke Get-MonitorInfo -Times 0 -Exactly
	}

	It "uses a supplied monitor snapshot instead of querying" {
		$script:Configuration = @{ SmallDisplayMachineType = 'Laptop' }

		Get-LayoutMachineType -MonitorInfo @([PSCustomObject]@{ IsPrimary = $true; Width = 1920; Height = 1080 }) |
			Should -BeExactly 'Laptop'

		Should -Invoke Get-MonitorInfo -Times 0 -Exactly
	}

	It "keeps the detected machine type when monitor detection yields nothing" {
		$script:Configuration = @{ SmallDisplayMachineType = 'Laptop' }
		Mock Get-MonitorInfo { @() }

		Get-LayoutMachineType | Should -BeExactly 'PC'
	}
}
