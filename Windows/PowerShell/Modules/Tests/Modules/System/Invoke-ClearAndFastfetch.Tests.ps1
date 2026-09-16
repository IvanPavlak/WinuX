#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Invoke-ClearAndFastfetch.ps1"
	. "$FunctionsPath\Resolve-FastfetchAutoFitSettings.ps1"
	. "$FunctionsPath\Get-ConsoleWindowSize.ps1"
	. "$FunctionsPath\Wait-ConsoleReflow.ps1"
	. "$FunctionsPath\Send-TerminalFontKey.ps1"
	. "$FunctionsPath\Test-FastfetchPanelOverflow.ps1"

	# fastfetch is an external binary absent on CI runners; stub it so Mock can attach
	# (no-op where fastfetch is installed).
	if (-not (Get-Command fastfetch -ErrorAction SilentlyContinue)) {
		function fastfetch { }
	}

	# Logging is a module concern; the function files are dot-sourced on their own here.
	if (-not (Get-Command Write-LogDebug -ErrorAction SilentlyContinue)) {
		function Write-LogDebug { param([string]$Message, [string]$Style) }
	}
	if (-not (Get-Command Write-LogWarning -ErrorAction SilentlyContinue)) {
		function Write-LogWarning { param([string]$Message) }
	}
	if (-not (Get-Command Test-LogVerbose -ErrorAction SilentlyContinue)) {
		function Test-LogVerbose { $false }
	}

	function New-WindowSize {
		param([int]$Width, [int]$Height)
		[pscustomobject]@{ Width = $Width; Height = $Height }
	}
}

Describe "Invoke-ClearAndFastfetch" {
	BeforeEach {
		Mock Clear-Host { }
		Mock fastfetch { }
		Mock Write-LogWarning { }

		# No keystroke may leave the suite: an unmocked Ctrl+0 / Ctrl+Minus lands in whatever
		# window has focus while the tests run.
		Mock Send-TerminalFontKey { }

		$script:OriginalWtSession = $env:WT_SESSION
		$script:SavedConfiguration = $global:Configuration
		# The base defaults, so the loop tests are independent of the machine's local overrides.
		$global:Configuration = @{ FastfetchAutoFit = @{ MaxShrinkSteps = 10; ReflowTimeoutMilliseconds = 10; PromptReserve = 1 } }
	}

	AfterEach {
		$env:WT_SESSION = $script:OriginalWtSession
		$global:Configuration = $script:SavedConfiguration
	}

	Context "outside Windows Terminal" {
		BeforeEach { $env:WT_SESSION = $null }

		It "clears terminal and invokes fastfetch once" {
			{ Invoke-ClearAndFastfetch } | Should -Not -Throw
			Should -Invoke Clear-Host -Times 1 -Exactly
			Should -Invoke fastfetch -Times 1 -Exactly
			Should -Invoke Send-TerminalFontKey -Times 0 -Exactly
		}
	}

	Context "with -NoResize" {
		BeforeEach { $env:WT_SESSION = "1" }

		It "skips auto-fit and invokes fastfetch once even inside Windows Terminal" {
			{ Invoke-ClearAndFastfetch -NoResize } | Should -Not -Throw
			Should -Invoke Clear-Host -Times 1 -Exactly
			Should -Invoke fastfetch -Times 1 -Exactly
			Should -Invoke Send-TerminalFontKey -Times 0 -Exactly
		}
	}

	Context "inside Windows Terminal" {
		BeforeEach {
			$env:WT_SESSION = "1"

			# No resolvable binary, so the measuring run falls back to the command name and the
			# real fastfetch is never spawned by the suite on a machine that has it installed.
			Mock Get-Command { $null } -ParameterFilter { $Name -eq "fastfetch" }
		}

		It "always clears and renders the panel without throwing" {
			# Auto-fit (font measurement / keystrokes) only engages when a real
			# console window is present; the clear + render must run regardless.
			{ Invoke-ClearAndFastfetch } | Should -Not -Throw
			Should -Invoke Clear-Host -Times 1 -Exactly
			Should -Invoke fastfetch
		}

		It "degrades to plain clear + fastfetch when the host has no console window" {
			Mock Get-ConsoleWindowSize { throw [IO.IOException]::new("The handle is invalid.") }

			{ Invoke-ClearAndFastfetch } | Should -Not -Throw
			Should -Invoke Clear-Host -Times 1 -Exactly
			Should -Invoke fastfetch -Times 1 -Exactly
			Should -Invoke Send-TerminalFontKey -Times 0 -Exactly
		}
	}

	Context "measuring the panel when the fastfetch binary is resolvable" {
		BeforeEach {
			$env:WT_SESSION = "1"

			# A stand-in binary that prints a two-line panel and exits. The measuring run has to go
			# to the BINARY, not to the `fastfetch` command name, so that a profile-defined
			# `fastfetch` function cannot distort the measurement with a decoration that has no
			# measurable width - an inline-image logo is a single enormous line.
			$script:FakeBinary = Join-Path $TestDrive "fastfetch-stand-in.cmd"
			Set-Content -LiteralPath $script:FakeBinary -Value @("@echo off", "echo panel row one", "echo panel row two")
			Mock Get-Command { [pscustomobject]@{ Source = $script:FakeBinary } } -ParameterFilter { $Name -eq "fastfetch" }
		}

		It "renders through the command name exactly once, so the measuring run bypassed the wrapper" {
			# One invocation of the mocked command name = the displaying run only. If the measuring
			# run also went through it, this would be two (or one when auto-fit does not engage,
			# which is why the assertion is an upper bound as well as a lower one).
			{ Invoke-ClearAndFastfetch } | Should -Not -Throw
			Should -Invoke Clear-Host -Times 1 -Exactly
			Should -Invoke fastfetch -Times 1 -Exactly
		}
	}

	Context "shrinking the font until the panel fits" {
		BeforeEach {
			$env:WT_SESSION = "1"

			# A 100-column, 3-row panel from a stand-in binary (the width is what overflows here).
			$script:FakeBinary = Join-Path $TestDrive "fastfetch-wide-panel.cmd"
			$wideRow = "x" * 100
			Set-Content -LiteralPath $script:FakeBinary -Value @("@echo off", "echo $wideRow", "echo row two", "echo row three")
			Mock Get-Command { [pscustomobject]@{ Source = $script:FakeBinary } } -ParameterFilter { $Name -eq "fastfetch" }

			# The console is scripted: the initial read, then one size per reflow wait, in order.
			# A drained queue keeps returning -Before, which is what a terminal that stopped
			# changing looks like.
			$script:InitialWindow = New-WindowSize -Width 80 -Height 30
			$script:ReflowQueue = @()
			Mock Get-ConsoleWindowSize { $script:InitialWindow }
			Mock Wait-ConsoleReflow {
				if ($script:ReflowQueue.Count -gt 0) {
					$next = $script:ReflowQueue[0]
					$script:ReflowQueue = @($script:ReflowQueue | Select-Object -Skip 1)
					return $next
				}
				return $Before
			}
		}

		It "resets the font and never shrinks when the panel fits at the default size" {
			$script:InitialWindow = New-WindowSize -Width 120 -Height 30
			$script:ReflowQueue = @()

			Invoke-ClearAndFastfetch

			Should -Invoke Send-TerminalFontKey -Times 1 -Exactly -ParameterFilter { $Action -eq "Reset" }
			Should -Invoke Send-TerminalFontKey -Times 0 -Exactly -ParameterFilter { $Action -eq "Decrease" }
			Should -Invoke fastfetch -Times 1 -Exactly
		}

		It "judges the fit against the DEFAULT font, not the font the call started at" {
			# The shell starts one step below the default (a previous `c` shrank it), where the panel
			# fits; the reset grows the window back to 80 columns, where it does not.
			$script:InitialWindow = New-WindowSize -Width 110 -Height 30
			$script:ReflowQueue = @(
				(New-WindowSize -Width 80 -Height 30)    # after Reset: default font, overflows
				(New-WindowSize -Width 110 -Height 30)   # after Decrease: fits
			)

			Invoke-ClearAndFastfetch

			Should -Invoke Send-TerminalFontKey -Times 1 -Exactly -ParameterFilter { $Action -eq "Decrease" }
		}

		It "shrinks as many steps as it takes for the panel to fit" {
			$script:ReflowQueue = @(
				(New-WindowSize -Width 80 -Height 30)    # after Reset: unchanged, already default
				(New-WindowSize -Width 88 -Height 32)    # step 1: still too narrow
				(New-WindowSize -Width 96 -Height 35)    # step 2: still too narrow
				(New-WindowSize -Width 106 -Height 38)   # step 3: fits
			)

			Invoke-ClearAndFastfetch

			Should -Invoke Send-TerminalFontKey -Times 1 -Exactly -ParameterFilter { $Action -eq "Reset" }
			Should -Invoke Send-TerminalFontKey -Times 3 -Exactly -ParameterFilter { $Action -eq "Decrease" }
			Should -Invoke Clear-Host -Times 1 -Exactly
			Should -Invoke fastfetch -Times 1 -Exactly
		}

		It "stops at the configured MaxShrinkSteps when the panel never fits" {
			$global:Configuration = @{ FastfetchAutoFit = @{ MaxShrinkSteps = 4 } }
			$script:ReflowQueue = @(1..8 | ForEach-Object { New-WindowSize -Width (80 + $_) -Height 30 })

			Invoke-ClearAndFastfetch

			Should -Invoke Send-TerminalFontKey -Times 4 -Exactly -ParameterFilter { $Action -eq "Decrease" }
			Should -Invoke fastfetch -Times 1 -Exactly
		}

		It "shrinks at most ten steps with the base configuration" {
			$script:ReflowQueue = @(1..20 | ForEach-Object { New-WindowSize -Width (80 + $_) -Height 30 })

			Invoke-ClearAndFastfetch

			Should -Invoke Send-TerminalFontKey -Times 10 -Exactly -ParameterFilter { $Action -eq "Decrease" }
		}

		It "lets an explicit -MaxShrinkSteps override the configured cap for one call" {
			$global:Configuration = @{ FastfetchAutoFit = @{ MaxShrinkSteps = 10 } }
			$script:ReflowQueue = @(1..20 | ForEach-Object { New-WindowSize -Width (80 + $_) -Height 30 })

			Invoke-ClearAndFastfetch -MaxShrinkSteps 2

			Should -Invoke Send-TerminalFontKey -Times 2 -Exactly -ParameterFilter { $Action -eq "Decrease" }
		}

		It "stops early when a step leaves the window unchanged, because the terminal is at its minimum font" {
			$script:ReflowQueue = @(
				(New-WindowSize -Width 80 -Height 30)    # after Reset
				(New-WindowSize -Width 90 -Height 30)    # step 1 took effect, still overflows
				(New-WindowSize -Width 90 -Height 30)    # step 2 changed nothing => minimum font
			)

			Invoke-ClearAndFastfetch

			Should -Invoke Send-TerminalFontKey -Times 2 -Exactly -ParameterFilter { $Action -eq "Decrease" }
			Should -Invoke fastfetch -Times 1 -Exactly
		}

		It "with -MaxShrinkSteps 0 resets the font and never shrinks, even when the panel overflows" {
			Invoke-ClearAndFastfetch -MaxShrinkSteps 0

			Should -Invoke Send-TerminalFontKey -Times 1 -Exactly -ParameterFilter { $Action -eq "Reset" }
			Should -Invoke Send-TerminalFontKey -Times 0 -Exactly -ParameterFilter { $Action -eq "Decrease" }
			Should -Invoke fastfetch -Times 1 -Exactly
		}

		It "counts the configured PromptReserve rows against the height" {
			# The panel (3 rows) fits a 120x5 window with a one-row reserve (3 <= 5 - 1 - 1) and
			# overflows it with the configured two-row reserve (3 > 5 - 1 - 2).
			$global:Configuration = @{ FastfetchAutoFit = @{ PromptReserve = 2 } }
			$script:InitialWindow = New-WindowSize -Width 120 -Height 5
			$script:ReflowQueue = @(
				(New-WindowSize -Width 120 -Height 5)
				(New-WindowSize -Width 130 -Height 6)
			)

			Invoke-ClearAndFastfetch

			Should -Invoke Send-TerminalFontKey -Times 1 -Exactly -ParameterFilter { $Action -eq "Decrease" }
		}

		It "lets an explicit -PromptReserve override the configured one" {
			$global:Configuration = @{ FastfetchAutoFit = @{ PromptReserve = 2 } }
			$script:InitialWindow = New-WindowSize -Width 120 -Height 5
			$script:ReflowQueue = @((New-WindowSize -Width 120 -Height 5))

			Invoke-ClearAndFastfetch -PromptReserve 1

			Should -Invoke Send-TerminalFontKey -Times 0 -Exactly -ParameterFilter { $Action -eq "Decrease" }
		}

		It "passes the configured reflow timeout to every wait" {
			$global:Configuration = @{ FastfetchAutoFit = @{ ReflowTimeoutMilliseconds = 750 } }
			$script:ReflowQueue = @(
				(New-WindowSize -Width 80 -Height 30)
				(New-WindowSize -Width 110 -Height 30)
			)

			Invoke-ClearAndFastfetch

			Should -Invoke Wait-ConsoleReflow -Times 2 -Exactly -ParameterFilter { $TimeoutMilliseconds -eq 750 }
		}

		It "lets an explicit -ReflowTimeoutMilliseconds override the configured one" {
			$global:Configuration = @{ FastfetchAutoFit = @{ ReflowTimeoutMilliseconds = 750 } }
			$script:ReflowQueue = @((New-WindowSize -Width 110 -Height 30))

			Invoke-ClearAndFastfetch -ReflowTimeoutMilliseconds 120

			Should -Invoke Wait-ConsoleReflow -Times 1 -Exactly -ParameterFilter { $TimeoutMilliseconds -eq 120 }
		}

		It "falls back to the built-in defaults when the configuration has no FastfetchAutoFit section" {
			$global:Configuration = @{}
			$script:ReflowQueue = @(1..20 | ForEach-Object { New-WindowSize -Width (80 + $_) -Height 30 })

			Invoke-ClearAndFastfetch

			Should -Invoke Send-TerminalFontKey -Times 10 -Exactly -ParameterFilter { $Action -eq "Decrease" }
			Should -Invoke Wait-ConsoleReflow -ParameterFilter { $TimeoutMilliseconds -eq 10 }
		}

		It "always clears and renders once, however many steps were taken" {
			$script:ReflowQueue = @(
				(New-WindowSize -Width 80 -Height 30)
				(New-WindowSize -Width 90 -Height 30)
				(New-WindowSize -Width 100 -Height 30)
			)

			Invoke-ClearAndFastfetch

			Should -Invoke Clear-Host -Times 1 -Exactly
			Should -Invoke fastfetch -Times 1 -Exactly
		}
	}
}
