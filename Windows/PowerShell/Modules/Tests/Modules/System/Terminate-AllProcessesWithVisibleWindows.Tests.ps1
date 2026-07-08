#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Terminate-AllProcessesWithVisibleWindows.ps1"

	# Stub Test-WindowTitleMatch since it's from the same module
	function Test-WindowTitleMatch { param($ProcessName, $WindowTitle, $Patterns) $false }
}

Describe "Terminate-AllProcessesWithVisibleWindows" {
	BeforeEach {
		Mock Write-Host { }
		Mock Stop-Process { }
	}

	Context "When processes with visible windows exist" {
		It "Should terminate non-excluded processes" {
			$mockProcesses = @(
				[PSCustomObject]@{ ProcessName = "notepad"; MainWindowTitle = "Untitled - Notepad"; Id = 100 }
			)
			Mock Get-Process { $mockProcesses }

			Terminate-AllProcessesWithVisibleWindows

			Should -Invoke Stop-Process -Times 1
		}

		It "Should skip default-excluded process names (firefox, Rainmeter, WindowsTerminal, obs64)" {
			$mockProcesses = @(
				[PSCustomObject]@{ ProcessName = "firefox"; MainWindowTitle = "Mozilla Firefox"; Id = 1 },
				[PSCustomObject]@{ ProcessName = "Rainmeter"; MainWindowTitle = "Rainmeter"; Id = 2 },
				[PSCustomObject]@{ ProcessName = "WindowsTerminal"; MainWindowTitle = "Terminal"; Id = 3 },
				[PSCustomObject]@{ ProcessName = "obs64"; MainWindowTitle = "OBS Studio"; Id = 4 },
				[PSCustomObject]@{ ProcessName = "notepad"; MainWindowTitle = "Note"; Id = 5 }
			)
			Mock Get-Process { $mockProcesses }

			Terminate-AllProcessesWithVisibleWindows

			Should -Invoke Stop-Process -Times 1
		}

		It "Should skip processes without a window title" {
			$mockProcesses = @(
				[PSCustomObject]@{ ProcessName = "svchost"; MainWindowTitle = ""; Id = 1 },
				[PSCustomObject]@{ ProcessName = "notepad"; MainWindowTitle = "Untitled"; Id = 2 }
			)
			Mock Get-Process { $mockProcesses }

			Terminate-AllProcessesWithVisibleWindows

			Should -Invoke Stop-Process -Times 1
		}
	}

	Context "When Exclude patterns are provided" {
		It "Should skip processes matching exclusion patterns" {
			$mockProcesses = @(
				[PSCustomObject]@{ ProcessName = "chrome"; MainWindowTitle = "YouTube - Chrome"; Id = 1 },
				[PSCustomObject]@{ ProcessName = "notepad"; MainWindowTitle = "Notes"; Id = 2 }
			)
			Mock Get-Process { $mockProcesses }
			Mock Test-WindowTitleMatch {
				param($ProcessName, $WindowTitle, $Patterns)
				$WindowTitle -match "YouTube"
			}

			Terminate-AllProcessesWithVisibleWindows -Exclude "*YouTube*"

			Should -Invoke Stop-Process -Times 1
		}
	}

	Context "When no visible-window processes exist" {
		It "Should not call Stop-Process" {
			Mock Get-Process { @() }

			Terminate-AllProcessesWithVisibleWindows

			Should -Invoke Stop-Process -Times 0
		}
	}
}
