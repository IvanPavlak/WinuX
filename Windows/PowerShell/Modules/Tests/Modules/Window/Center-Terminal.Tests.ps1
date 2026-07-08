#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Resolve-CenteredWindowPercent.ps1"
	. "$FunctionsPath\Center-Terminal.ps1"

	# Stub the external dependencies so the orchestration can be tested in isolation.
	function Get-MonitorInfo { param([switch]$Quiet) }
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
		$global:Configuration = @{
			CenterTerminalSizing = @{
				TargetWidthPx    = 1376
				TargetHeightPx   = 700
				MinWidthPercent  = 25
				MaxWidthPercent  = 72
				MinHeightPercent = 35
				MaxHeightPercent = 75
			}
		}
		Mock Center-Windows { }
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
}
