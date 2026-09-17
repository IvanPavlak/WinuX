#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Show-TerminalGreeting.ps1"
	. "$FunctionsPath\Resolve-TerminalGreetingSettings.ps1"

	# The three steps are mocked outright: this suite is about the orchestration - which steps run,
	# in what order, and what the fastfetch step is told about onefetch's height. Each step has its
	# own suite for what it does.
	. "$FunctionsPath\Invoke-Clear.ps1"
	. "$FunctionsPath\Invoke-Fastfetch.ps1"
	. "$FunctionsPath\Invoke-Onefetch.ps1"

	if (-not (Get-Command Write-LogDebug -ErrorAction SilentlyContinue)) {
		function Write-LogDebug { param([string]$Message, [string]$Style) }
	}
	if (-not (Get-Command Write-LogWarning -ErrorAction SilentlyContinue)) {
		function Write-LogWarning { param([string]$Message) }
	}
}

Describe "Show-TerminalGreeting" {
	BeforeEach {
		$script:Calls = [System.Collections.ArrayList]@()
		$script:ExtraRowsSeen = $null
		$script:NoResizeSeen = $null

		Mock Invoke-Clear { [void]$script:Calls.Add("Clear") }
		Mock Invoke-Fastfetch {
			[void]$script:Calls.Add("Fastfetch")
			$script:ExtraRowsSeen = $ExtraRows
			$script:NoResizeSeen = [bool]$NoResize
		}
		Mock Invoke-Onefetch {
			if ($Measure) { [void]$script:Calls.Add("Measure"); return 7 }
			[void]$script:Calls.Add("Onefetch")
		}

		$script:SavedConfiguration = $global:Configuration
		# Onefetch on, so the interesting path is the default one for this suite.
		$global:Configuration = @{ TerminalGreeting = @{ Onefetch = @{ Enabled = $true } } }
	}

	AfterEach { $global:Configuration = $script:SavedConfiguration }

	Context "the order of the steps" {
		It "measures onefetch, then clears, then fastfetch, then onefetch" {
			# Measuring first is what makes the font fit both panels; clearing before the shrink
			# keystrokes means they happen on an empty screen.
			Show-TerminalGreeting

			$script:Calls | Should -Be @("Measure", "Clear", "Fastfetch", "Onefetch")
		}

		It "runs each step exactly once" {
			Show-TerminalGreeting

			Should -Invoke Invoke-Clear -Times 1 -Exactly
			Should -Invoke Invoke-Fastfetch -Times 1 -Exactly
			Should -Invoke Invoke-Onefetch -Times 2 -Exactly -Because "once to measure, once to display"
		}
	}

	Context "the onefetch fit budget" {
		It "passes the measured rows to Invoke-Fastfetch as -ExtraRows" {
			Show-TerminalGreeting

			$script:ExtraRowsSeen | Should -Be 7
		}

		It "passes 0 when IncludeInAutoFit is off, so fastfetch is fitted alone" {
			$global:Configuration = @{ TerminalGreeting = @{ Onefetch = @{ Enabled = $true; IncludeInAutoFit = $false } } }

			Show-TerminalGreeting

			$script:ExtraRowsSeen | Should -Be 0
			$script:Calls | Should -Be @("Clear", "Fastfetch", "Onefetch")
		}

		It "does not measure when there is no fit to inform" {
			# -NoResize is the startup path; measuring would spawn onefetch for nothing.
			Show-TerminalGreeting -NoResize

			$script:Calls | Should -Be @("Clear", "Fastfetch", "Onefetch")
			$script:ExtraRowsSeen | Should -Be 0
		}

		It "forwards -NoResize to Invoke-Fastfetch" {
			Show-TerminalGreeting -NoResize

			$script:NoResizeSeen | Should -BeTrue
		}

		It "does not pass -NoResize when it was not asked for" {
			Show-TerminalGreeting

			$script:NoResizeSeen | Should -BeFalse
		}
	}

	Context "the per-call -No* switches" {
		It "-NoClear skips exactly the clear step" {
			Show-TerminalGreeting -NoClear

			$script:Calls | Should -Be @("Measure", "Fastfetch", "Onefetch")
		}

		It "-NoFastfetch skips exactly the fastfetch step, and the measurement it informed" {
			Show-TerminalGreeting -NoFastfetch

			$script:Calls | Should -Be @("Clear", "Onefetch")
		}

		It "-NoOnefetch skips both the measurement and the display" {
			Show-TerminalGreeting -NoOnefetch

			$script:Calls | Should -Be @("Clear", "Fastfetch")
			$script:ExtraRowsSeen | Should -Be 0
		}

		It "all three switches together leave nothing to do" {
			Show-TerminalGreeting -NoClear -NoFastfetch -NoOnefetch

			$script:Calls | Should -BeNullOrEmpty
		}
	}

	Context "a step disabled in configuration" {
		It "leaves the skipping to the step itself, which owns its own reason" {
			# The orchestrator does not read Enabled flags: each Invoke-* is handed the settings and
			# returns early on its own, so a step behaves identically called directly or through
			# the greeting. What the orchestrator must do is hand the settings over.
			$global:Configuration = @{ TerminalGreeting = @{ Clear = @{ Enabled = $false }; Onefetch = @{ Enabled = $true } } }

			Show-TerminalGreeting

			Should -Invoke Invoke-Clear -Times 1 -Exactly -ParameterFilter { $Settings.Clear.Enabled -eq $false }
		}

		It "hands the same resolved settings to every step" {
			Show-TerminalGreeting

			Should -Invoke Invoke-Fastfetch -Times 1 -Exactly -ParameterFilter { $null -ne $Settings -and $Settings.Onefetch.Enabled }
			Should -Invoke Invoke-Onefetch -ParameterFilter { $null -ne $Settings }
		}

		It "adds nothing to the fit budget when onefetch is off in configuration" {
			# The orchestrator still asks; Invoke-Onefetch -Measure answers 0 for a disabled step,
			# so the budget is right without the orchestrator duplicating the flag.
			Mock Invoke-Onefetch {
				if ($Measure) { [void]$script:Calls.Add("Measure"); return 0 }
				[void]$script:Calls.Add("Onefetch")
			}
			$global:Configuration = @{ TerminalGreeting = @{ Onefetch = @{ Enabled = $false } } }

			Show-TerminalGreeting

			$script:ExtraRowsSeen | Should -Be 0
		}
	}

	Context "the auto-fit knobs" {
		It "forwards -<Name> into the settings every step is handed" -ForEach @(
			@{ Name = "MaxShrinkSteps"; Value = 2 }
			@{ Name = "PromptReserve"; Value = 3 }
			@{ Name = "ReflowTimeoutMilliseconds"; Value = 250 }
		) {
			$overrides = @{ $Name = $Value }

			Show-TerminalGreeting @overrides

			Should -Invoke Invoke-Fastfetch -Times 1 -Exactly -ParameterFilter {
				$Settings.Fastfetch.AutoFit.$Name -eq $Value
			}
		}
	}

	Context "a configuration with no TerminalGreeting section" {
		It "falls back to the shipped defaults: clear and fastfetch, no onefetch" {
			# A fork that has not migrated its Configuration.local.psd1 keeps the previous behavior.
			$global:Configuration = @{}
			Mock Invoke-Onefetch {
				if ($Measure) { [void]$script:Calls.Add("Measure"); return 0 }
				[void]$script:Calls.Add("Onefetch")
			}

			Show-TerminalGreeting

			Should -Invoke Invoke-Clear -Times 1 -Exactly
			Should -Invoke Invoke-Fastfetch -Times 1 -Exactly -ParameterFilter {
				$Settings.Fastfetch.Enabled -and $Settings.Fastfetch.AutoFit.MaxShrinkSteps -eq 10
			}
			$script:ExtraRowsSeen | Should -Be 0
		}

		It "does not throw" {
			$global:Configuration = $null

			{ Show-TerminalGreeting } | Should -Not -Throw
		}
	}
}
