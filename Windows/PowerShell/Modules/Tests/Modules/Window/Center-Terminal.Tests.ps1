#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Resolve-CenteredWindowPercent.ps1"
	# The real sizing resolvers, not mocks: which block a given display resolves to is part of
	# what Center-Terminal is being tested for.
	. "$FunctionsPath\Resolve-DisplayAwareProfile.ps1"
	. "$FunctionsPath\Resolve-CenterTerminalSizing.ps1"
	. "$FunctionsPath\Center-Terminal.ps1"

	# Stub the external dependencies so the orchestration can be tested in isolation.
	function Get-MonitorInfo { param([switch]$Quiet) }
	function Get-LayoutMachineType { param([object[]]$MonitorInfo) }
	function Test-SmallPrimaryDisplay { param([object[]]$MonitorInfo, [int]$MaxWidthPx) }
	function Center-Windows {
		param(
			[int]$WidthPercent,
			[int]$HeightPercent,
			[string]$ProcessName,
			[string]$WindowTitle,
			[switch]$OnPrimary
		)
	}
}

Describe "Center-Terminal" {
	BeforeEach {
		# The keyed shape the base configuration ships, with the shipped values under Default -
		# so every assertion below is also a check that the keyed default behaves exactly like
		# the flat section it replaced.
		$global:Configuration = @{
			CenterTerminalSizing = @{
				Default = @{
					TargetWidthPx    = 1376
					TargetHeightPx   = 700
					MinWidthPercent  = 25
					MaxWidthPercent  = 72
					MinHeightPercent = 35
					MaxHeightPercent = 75
				}
			}
		}
		Mock Center-Windows { }
		Mock Get-LayoutMachineType { 'PC' }
		Mock Test-SmallPrimaryDisplay { $false }
	}

	It "centers Windows Terminal on the primary monitor" {
		Mock Get-MonitorInfo { [PSCustomObject]@{ IsPrimary = $true; WorkAreaWidth = 3440; WorkAreaHeight = 1400 } }

		Center-Terminal

		Should -Invoke Center-Windows -Times 1 -Exactly -ParameterFilter {
			$ProcessName -eq "WindowsTerminal" -and $OnPrimary
		}
	}

	It "derives the adaptive size from the live primary monitor (1920x1040 => 72/67)" {
		Mock Get-MonitorInfo { [PSCustomObject]@{ IsPrimary = $true; WorkAreaWidth = 1920; WorkAreaHeight = 1040 } }

		Center-Terminal

		Should -Invoke Center-Windows -ParameterFilter { $WidthPercent -eq 72 -and $HeightPercent -eq 67 }
	}

	It "keeps the ultrawide at the legacy 40/50" {
		Mock Get-MonitorInfo { [PSCustomObject]@{ IsPrimary = $true; WorkAreaWidth = 3440; WorkAreaHeight = 1400 } }

		Center-Terminal

		Should -Invoke Center-Windows -ParameterFilter { $WidthPercent -eq 40 -and $HeightPercent -eq 50 }
	}

	It "falls back to 40/50 when the config section is absent" {
		$global:Configuration = @{}
		Mock Get-MonitorInfo { [PSCustomObject]@{ IsPrimary = $true; WorkAreaWidth = 1920; WorkAreaHeight = 1040 } }

		Center-Terminal

		Should -Invoke Center-Windows -ParameterFilter { $WidthPercent -eq 40 -and $HeightPercent -eq 50 }
	}

	It "falls back to 40/50 when no monitors are detected" {
		Mock Get-MonitorInfo { @() }

		Center-Terminal

		Should -Invoke Center-Windows -ParameterFilter { $WidthPercent -eq 40 -and $HeightPercent -eq 50 }
	}

	It "falls back to 40/50 when the keyed section has no row for this machine" {
		$global:Configuration.CenterTerminalSizing = @{ Work = @{ TargetWidthPx = 1376; TargetHeightPx = 700; MinWidthPercent = 25; MaxWidthPercent = 72; MinHeightPercent = 35; MaxHeightPercent = 75 } }
		Mock Get-MonitorInfo { [PSCustomObject]@{ IsPrimary = $true; WorkAreaWidth = 1920; WorkAreaHeight = 1040 } }

		Center-Terminal

		Should -Invoke Center-Windows -ParameterFilter { $WidthPercent -eq 40 -and $HeightPercent -eq 50 }
	}

	Context "per-machine sizing" {
		It "still accepts the legacy flat section" {
			# Upstream configs (and anyone who has not migrated) keep the flat shape.
			$global:Configuration.CenterTerminalSizing = @{
				TargetWidthPx    = 1376
				TargetHeightPx   = 700
				MinWidthPercent  = 25
				MaxWidthPercent  = 72
				MinHeightPercent = 35
				MaxHeightPercent = 75
			}
			Mock Get-MonitorInfo { [PSCustomObject]@{ IsPrimary = $true; WorkAreaWidth = 1920; WorkAreaHeight = 1040 } }

			Center-Terminal

			Should -Invoke Center-Windows -ParameterFilter { $WidthPercent -eq 72 -and $HeightPercent -eq 67 }
		}

		It "prefers the row for the resolved machine type over Default" {
			$global:Configuration.CenterTerminalSizing.PC = @{
				TargetWidthPx = 688; TargetHeightPx = 350
				MinWidthPercent = 10; MaxWidthPercent = 72
				MinHeightPercent = 10; MaxHeightPercent = 75
			}
			Mock Get-MonitorInfo { [PSCustomObject]@{ IsPrimary = $true; WorkAreaWidth = 3440; WorkAreaHeight = 1400 } }

			Center-Terminal

			# Half the ultrawide target => half the percentages the Default row would give.
			Should -Invoke Center-Windows -ParameterFilter { $WidthPercent -eq 20 -and $HeightPercent -eq 25 }
		}

		It "prefers the SmallDisplay row on a laptop-class panel" {
			$global:Configuration.CenterTerminalSizing.SmallDisplay = @{
				TargetWidthPx = 1152; TargetHeightPx = 624
				MinWidthPercent = 10; MaxWidthPercent = 90
				MinHeightPercent = 10; MaxHeightPercent = 90
			}
			Mock Test-SmallPrimaryDisplay { $true }
			Mock Get-MonitorInfo { [PSCustomObject]@{ IsPrimary = $true; WorkAreaWidth = 1920; WorkAreaHeight = 1040 } }

			Center-Terminal

			Should -Invoke Center-Windows -ParameterFilter { $WidthPercent -eq 60 -and $HeightPercent -eq 60 }
		}

		It "reuses the monitor snapshot it already captured" {
			Mock Get-MonitorInfo { [PSCustomObject]@{ IsPrimary = $true; WorkAreaWidth = 3440; WorkAreaHeight = 1400 } }
			$global:Configuration.CenterTerminalSizing.SmallDisplay = @{ TargetWidthPx = 1152; TargetHeightPx = 624; MinWidthPercent = 10; MaxWidthPercent = 90; MinHeightPercent = 10; MaxHeightPercent = 90 }

			Center-Terminal

			Should -Invoke Get-MonitorInfo -Times 1 -Exactly
			Should -Invoke Test-SmallPrimaryDisplay -Times 1 -Exactly -ParameterFilter { $null -ne $MonitorInfo }
		}
	}
}
