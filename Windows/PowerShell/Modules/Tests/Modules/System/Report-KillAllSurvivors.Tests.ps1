#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Report-KillAllSurvivors.ps1"
	# Discovery and pattern matching are module siblings; loaded so Mock can attach - the tests
	# never let the discovery touch the real desktop.
	. "$FunctionsPath\Get-VisibleWindowProcess.ps1"
	. "$FunctionsPath\Test-WindowTitleMatch.ps1"

	$script:OriginalConfiguration = $global:Configuration
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Report-KillAllSurvivors" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogWarning { }
		Mock Write-LogList { }
		Mock Get-VisibleWindowProcess { @() }

		$global:Configuration = @{
			Universal = @{
				VisibleWindowExclusions = @("WindowsTerminal", "Rainmeter")
			}
		}
	}

	It "returns nothing and prints nothing when the desktop is clean" {
		$result = @(Report-KillAllSurvivors)

		$result.Count | Should -Be 0
		Should -Invoke Write-LogWarning -Times 0
		Should -Invoke Write-LogList -Times 0
	}

	It "does not count the configured exclusions as survivors" {
		Mock Get-VisibleWindowProcess {
			@(
				[PSCustomObject]@{ ProcessName = "WindowsTerminal"; Id = 1; WindowTitles = @("pwsh"); MainWindowTitle = "pwsh" },
				[PSCustomObject]@{ ProcessName = "Rainmeter"; Id = 2; WindowTitles = @("Rainmeter"); MainWindowTitle = "Rainmeter" }
			)
		}

		@(Report-KillAllSurvivors).Count | Should -Be 0
		Should -Invoke Write-LogWarning -Times 0
	}

	It "reports every remaining window, one line each, and returns them" {
		Mock Get-VisibleWindowProcess {
			@(
				[PSCustomObject]@{ ProcessName = "firefox"; Id = 10; WindowTitles = @("Close all tabs?", "Mail - Mozilla Firefox"); MainWindowTitle = "Close all tabs?" },
				[PSCustomObject]@{ ProcessName = "Code"; Id = 11; WindowTitles = @("Save changes?"); MainWindowTitle = "Save changes?" }
			)
		}

		$result = @(Report-KillAllSurvivors)

		$result.Count | Should -Be 3
		$result[0].ProcessName | Should -Be "firefox"
		$result[0].Title | Should -Be "Close all tabs?"
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match "^3 window\(s\) survived" }
		Should -Invoke Write-LogList -Times 1 -Exactly -ParameterFilter {
			@($Items).Count -eq 3 -and @($Items)[2] -match "Save changes\? \(Code, PID 11\)"
		}
	}

	It "does not count windows the run was told to keep" {
		Mock Get-VisibleWindowProcess {
			@([PSCustomObject]@{ ProcessName = "chrome"; Id = 20; WindowTitles = @("YouTube - Google Chrome", "Docs - Google Chrome"); MainWindowTitle = "YouTube - Google Chrome" })
		}

		$result = @(Report-KillAllSurvivors -Exclude "*YouTube*")

		# The kept window is expected; its sibling is a genuine survivor.
		$result.Count | Should -Be 1
		$result[0].Title | Should -Be "Docs - Google Chrome"
	}

	It "matches exclusion patterns against the process name as well as the title" {
		Mock Get-VisibleWindowProcess {
			@([PSCustomObject]@{ ProcessName = "obsidian"; Id = 30; WindowTitles = @("Notes"); MainWindowTitle = "Notes" })
		}

		@(Report-KillAllSurvivors -Exclude "obsidian").Count | Should -Be 0
	}
}
