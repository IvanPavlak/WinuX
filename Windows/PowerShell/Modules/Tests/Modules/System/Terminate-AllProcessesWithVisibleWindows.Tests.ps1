#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Terminate-AllProcessesWithVisibleWindows.ps1"
	# Candidate discovery lives in Get-VisibleWindowProcess; load it so Mock can attach - the
	# tests below never let it enumerate the developer's real desktop.
	. "$FunctionsPath\Get-VisibleWindowProcess.ps1"

	# Stub Test-WindowTitleMatch since it's from the same module
	function Test-WindowTitleMatch { param($ProcessName, $WindowTitle, $Patterns) $false }

	$script:OriginalConfiguration = $global:Configuration
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Terminate-AllProcessesWithVisibleWindows" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogWarning { }
		Mock Write-LogList { }
		Mock Write-LogSuccess { }
		Mock Stop-Process { }
		# Every kill takes: nothing to wait for, nothing left running.
		Mock Wait-Process { }
		Mock Get-Process { $null }
		Mock Get-VisibleWindowProcess { @() }
		$script:VisibleWindowTerminationWaitSeconds = 0

		$global:Configuration = @{
			Universal = @{
				VisibleWindowExclusions = @(
					"Rainmeter"
					"WindowsTerminal"
					"Docker Desktop"
					"obs64"
					"PowerToys"
					"PowerToys.FancyZones"
					"PowerToys.Settings"
				)
				Browsers                = @{
					Firefox = @{ Exe = "C:\Program Files\Mozilla Firefox\firefox.exe" }
				}
			}
		}
	}

	Context "When processes with visible windows exist" {
		It "Should terminate non-excluded processes" {
			Mock Get-VisibleWindowProcess {
				@([PSCustomObject]@{ ProcessName = "notepad"; Id = 100; WindowTitles = @("Untitled - Notepad"); MainWindowTitle = "Untitled - Notepad" })
			}

			Terminate-AllProcessesWithVisibleWindows

			Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 100 -and $Force }
		}

		It "Should skip default-excluded process names (firefox, Rainmeter, WindowsTerminal, obs64)" {
			Mock Get-VisibleWindowProcess {
				@(
					[PSCustomObject]@{ ProcessName = "firefox"; Id = 1; WindowTitles = @("Mozilla Firefox"); MainWindowTitle = "Mozilla Firefox" },
					[PSCustomObject]@{ ProcessName = "Rainmeter"; Id = 2; WindowTitles = @("Rainmeter"); MainWindowTitle = "Rainmeter" },
					[PSCustomObject]@{ ProcessName = "WindowsTerminal"; Id = 3; WindowTitles = @("Terminal"); MainWindowTitle = "Terminal" },
					[PSCustomObject]@{ ProcessName = "obs64"; Id = 4; WindowTitles = @("OBS Studio"); MainWindowTitle = "OBS Studio" },
					[PSCustomObject]@{ ProcessName = "notepad"; Id = 5; WindowTitles = @("Note"); MainWindowTitle = "Note" }
				)
			}

			Terminate-AllProcessesWithVisibleWindows

			Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 5 }
		}

		It "Should discover candidates from the window side, not from Get-Process" {
			# The whole point of the helper: a process is a candidate because a window of its is on
			# screen, regardless of what .NET considers its main window.
			Mock Get-VisibleWindowProcess {
				@([PSCustomObject]@{ ProcessName = "claude"; Id = 6; WindowTitles = @("Claude"); MainWindowTitle = "Claude" })
			}

			Terminate-AllProcessesWithVisibleWindows

			Should -Invoke Get-VisibleWindowProcess -Times 1 -Exactly
			Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 6 }
		}
	}

	Context "When Exclude patterns are provided" {
		It "Should skip processes matching exclusion patterns" {
			Mock Get-VisibleWindowProcess {
				@(
					[PSCustomObject]@{ ProcessName = "chrome"; Id = 1; WindowTitles = @("YouTube - Chrome"); MainWindowTitle = "YouTube - Chrome" },
					[PSCustomObject]@{ ProcessName = "notepad"; Id = 2; WindowTitles = @("Notes"); MainWindowTitle = "Notes" }
				)
			}
			Mock Test-WindowTitleMatch {
				param($ProcessName, $WindowTitle, $Patterns)
				$WindowTitle -match "YouTube"
			}

			Terminate-AllProcessesWithVisibleWindows -Exclude "*YouTube*"

			Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 2 }
		}

		It "Should spare a multi-window process when ANY of its windows matches" {
			# A force-kill is per process: the kept window cannot survive without its siblings.
			Mock Get-VisibleWindowProcess {
				@([PSCustomObject]@{ ProcessName = "Code"; Id = 7; WindowTitles = @("scratch - Code", "Important Project - Code"); MainWindowTitle = "scratch - Code" })
			}
			Mock Test-WindowTitleMatch {
				param($ProcessName, $WindowTitle, $Patterns)
				$WindowTitle -match "Important Project"
			}

			Terminate-AllProcessesWithVisibleWindows -Exclude "*Important Project*"

			Should -Invoke Stop-Process -Times 0
		}
	}

	Context "Verification after the kill" {
		It "Should wait for the killed processes and report success when they are gone" {
			Mock Get-VisibleWindowProcess {
				@([PSCustomObject]@{ ProcessName = "notepad"; Id = 100; WindowTitles = @("Untitled"); MainWindowTitle = "Untitled" })
			}

			Terminate-AllProcessesWithVisibleWindows

			Should -Invoke Wait-Process -Times 1 -Exactly -ParameterFilter { @($Id) -contains 100 }
			Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -match "successfully" }
			Should -Invoke Write-LogWarning -Times 0
		}

		It "Should report a process that is still running instead of declaring success" {
			Mock Get-VisibleWindowProcess {
				@(
					[PSCustomObject]@{ ProcessName = "notepad"; Id = 100; WindowTitles = @("Untitled"); MainWindowTitle = "Untitled" },
					[PSCustomObject]@{ ProcessName = "Taskmgr"; Id = 200; WindowTitles = @("Task Manager"); MainWindowTitle = "Task Manager" }
				)
			}
			# The elevated one shrugged off the kill.
			Mock Get-Process { [PSCustomObject]@{ Id = 200 } } -ParameterFilter { $Id -eq 200 }

			Terminate-AllProcessesWithVisibleWindows

			Should -Invoke Write-LogSuccess -Times 0
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match "1 process\(es\) with visible windows could not be terminated" }
			Should -Invoke Write-LogList -Times 1 -Exactly -ParameterFilter { @($Items) -match "Taskmgr" }
		}
	}

	Context "When no visible-window processes exist" {
		It "Should not call Stop-Process" {
			Mock Get-VisibleWindowProcess { @() }

			Terminate-AllProcessesWithVisibleWindows

			Should -Invoke Stop-Process -Times 0
			Should -Invoke Wait-Process -Times 0
		}
	}

	Context "When no exclusions are configured" {
		It "Should terminate nothing when the exclusion list is absent" {
			$global:Configuration = @{ Universal = @{ } }
			Mock Get-VisibleWindowProcess { [PSCustomObject]@{ ProcessName = "notepad"; Id = 1; WindowTitles = @("Untitled"); MainWindowTitle = "Untitled" } }

			Terminate-AllProcessesWithVisibleWindows

			Should -Invoke Stop-Process -Times 0
			Should -Invoke Get-VisibleWindowProcess -Times 0
		}

		It "Should terminate nothing when the exclusion list is empty" {
			$global:Configuration = @{
				Universal = @{
					VisibleWindowExclusions = @()
				}
			}
			Mock Get-VisibleWindowProcess { [PSCustomObject]@{ ProcessName = "notepad"; Id = 1; WindowTitles = @("Untitled"); MainWindowTitle = "Untitled" } }

			Terminate-AllProcessesWithVisibleWindows

			Should -Invoke Stop-Process -Times 0
			Should -Invoke Get-VisibleWindowProcess -Times 0
		}
	}
}
