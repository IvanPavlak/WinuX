#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Resolve-TerminalGreetingSettings.ps1"

	# Logging is a module concern; the function file is dot-sourced on its own here.
	if (-not (Get-Command Write-LogDebug -ErrorAction SilentlyContinue)) {
		function Write-LogDebug { param([string]$Message, [string]$Style) }
	}
	if (-not (Get-Command Write-LogWarning -ErrorAction SilentlyContinue)) {
		function Write-LogWarning { param([string]$Message) }
	}
}

Describe "Resolve-TerminalGreetingSettings" {
	# Created once for the whole Describe. Write-LogDebug is mocked too: in a suite worker the
	# Logging module is loaded, so the real one ran - a call-stack walk and a session-log append
	# for each of the dozen debug lines every resolve writes, which was most of this file's run
	# time and left test output in the developer's session log. Should -Invoke still counts per It.
	BeforeAll {
		Mock Write-LogWarning { }
		Mock Write-LogDebug { }
	}

	BeforeEach {
		$script:SavedConfiguration = $global:Configuration
		$global:Configuration = @{}
	}

	AfterEach { $global:Configuration = $script:SavedConfiguration }

	Context "built-in defaults" {
		It "returns the shipped defaults when the section is missing entirely" {
			# A configuration with no TerminalGreeting section must behave exactly like the base,
			# or the documented defaults become a lie for anyone reading either place.
			$settings = Resolve-TerminalGreetingSettings

			$settings.Clear.Enabled | Should -BeTrue
			$settings.Fastfetch.Enabled | Should -BeTrue
			$settings.Fastfetch.AutoFit.Enabled | Should -BeTrue
			$settings.Fastfetch.AutoFit.MaxShrinkSteps | Should -Be 10
			$settings.Fastfetch.AutoFit.ReflowTimeoutMilliseconds | Should -Be 10
			$settings.Fastfetch.AutoFit.PromptReserve | Should -Be 1
			$settings.Onefetch.IncludeInAutoFit | Should -BeTrue
			$settings.Onefetch.InProjectTerminals | Should -BeTrue
			$settings.Onefetch.Arguments | Should -BeNullOrEmpty
		}

		It "ships onefetch OFF, because it needs a binary and a repository" {
			(Resolve-TerminalGreetingSettings).Onefetch.Enabled | Should -BeFalse
		}

		It "returns the defaults for an empty section" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{}

			$settings.Fastfetch.AutoFit.MaxShrinkSteps | Should -Be 10
			$settings.Onefetch.Enabled | Should -BeFalse
		}

		It "returns the defaults for a branch written as something other than a hashtable" {
			# Degrade rather than throw at the prompt.
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Fastfetch = "yes"; Onefetch = @(1, 2) }

			$settings.Fastfetch.Enabled | Should -BeTrue
			$settings.Fastfetch.AutoFit.MaxShrinkSteps | Should -Be 10
			$settings.Onefetch.Enabled | Should -BeFalse
		}

		It "returns the three integers as [int]" {
			$autoFit = (Resolve-TerminalGreetingSettings).Fastfetch.AutoFit

			$autoFit.MaxShrinkSteps | Should -BeOfType [int]
			$autoFit.ReflowTimeoutMilliseconds | Should -BeOfType [int]
			$autoFit.PromptReserve | Should -BeOfType [int]
		}
	}

	Context "the configuration layer" {
		It "reads <Path> from configuration" -ForEach @(
			@{ Path = "MaxShrinkSteps"; Value = 3 }
			@{ Path = "ReflowTimeoutMilliseconds"; Value = 750 }
			@{ Path = "PromptReserve"; Value = 2 }
		) {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Fastfetch = @{ AutoFit = @{ $Path = $Value } } }

			$settings.Fastfetch.AutoFit.$Path | Should -Be $Value
		}

		It "defaults to $global:Configuration.TerminalGreeting when -Settings is not passed" {
			$global:Configuration = @{ TerminalGreeting = @{ Onefetch = @{ Enabled = $true } } }

			(Resolve-TerminalGreetingSettings).Onefetch.Enabled | Should -BeTrue
		}

		It "parses an integer written as a string" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Fastfetch = @{ AutoFit = @{ MaxShrinkSteps = "4" } } }

			$settings.Fastfetch.AutoFit.MaxShrinkSteps | Should -Be 4
		}

		It "treats a `$null value as 'use the default', silently" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Fastfetch = @{ AutoFit = @{ PromptReserve = $null } } }

			$settings.Fastfetch.AutoFit.PromptReserve | Should -Be 1
			Should -Invoke Write-LogWarning -Times 0 -Exactly
		}

		It "leaves the other keys at their defaults when one is set" {
			# The section deep-merges per key; setting one must not reset the rest.
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Fastfetch = @{ AutoFit = @{ PromptReserve = 2 } } }

			$settings.Fastfetch.AutoFit.MaxShrinkSteps | Should -Be 10
			$settings.Fastfetch.AutoFit.ReflowTimeoutMilliseconds | Should -Be 10
			$settings.Clear.Enabled | Should -BeTrue
		}
	}

	Context "the boolean flags" {
		It "reads <Branch>.<Key> = `$false from configuration" -ForEach @(
			@{ Branch = "Clear"; Key = "Enabled" }
			@{ Branch = "Fastfetch"; Key = "Enabled" }
			@{ Branch = "Onefetch"; Key = "IncludeInAutoFit" }
			@{ Branch = "Onefetch"; Key = "InProjectTerminals" }
		) {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ $Branch = @{ $Key = $false } }

			$settings.$Branch.$Key | Should -BeFalse
		}

		It "reads Fastfetch.AutoFit.Enabled = `$false" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Fastfetch = @{ AutoFit = @{ Enabled = $false } } }

			$settings.Fastfetch.AutoFit.Enabled | Should -BeFalse
			$settings.Fastfetch.Enabled | Should -BeTrue -Because "turning the fit off is not turning the panel off"
		}

		It "reads Onefetch.Enabled = `$true, which is the one flag a fork usually flips" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Onefetch = @{ Enabled = $true } }

			$settings.Onefetch.Enabled | Should -BeTrue
		}

		It "reads a truthy non-boolean the way a psd1 author would expect" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Onefetch = @{ Enabled = 1 } }

			$settings.Onefetch.Enabled | Should -BeTrue
		}
	}

	Context "the Arguments array" {
		It "passes an array through in order" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Onefetch = @{ Arguments = @("--no-art", "--no-merges") } }

			$settings.Onefetch.Arguments | Should -Be @("--no-art", "--no-merges")
		}

		It "accepts a single string as one argument" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Onefetch = @{ Arguments = "--no-art" } }

			$settings.Onefetch.Arguments | Should -Be @("--no-art")
		}

		It "drops blank entries, so a trailing comma in the psd1 cannot pass an empty argument" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Onefetch = @{ Arguments = @("--no-art", "", "  ") } }

			$settings.Onefetch.Arguments | Should -Be @("--no-art")
		}

		It "returns an empty array, not `$null, when nothing is configured" {
			(Resolve-TerminalGreetingSettings).Onefetch.Arguments.Count | Should -Be 0
		}
	}

	Context "the explicit-parameter layer" {
		It "lets -<Path> beat the configured value" -ForEach @(
			@{ Path = "MaxShrinkSteps"; Configured = 3; Passed = 7 }
			@{ Path = "ReflowTimeoutMilliseconds"; Configured = 750; Passed = 120 }
			@{ Path = "PromptReserve"; Configured = 2; Passed = 0 }
		) {
			$overrides = @{ $Path = $Passed }
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Fastfetch = @{ AutoFit = @{ $Path = $Configured } } } @overrides

			$settings.Fastfetch.AutoFit.$Path | Should -Be $Passed
		}

		It "leaves the configured value alone for a parameter that was not passed" {
			$settings = Resolve-TerminalGreetingSettings `
				-Settings @{ Fastfetch = @{ AutoFit = @{ MaxShrinkSteps = 3; PromptReserve = 2 } } } `
				-MaxShrinkSteps 7

			$settings.Fastfetch.AutoFit.PromptReserve | Should -Be 2
		}
	}

	Context "the Onefetch.Style branch" {
		It "ships off, with nothing to rewrite" {
			$style = (Resolve-TerminalGreetingSettings -Settings @{}).Onefetch.Style

			$style.Enabled | Should -BeFalse
			$style.Separator | Should -BeNullOrEmpty
			$style.Colors.Count | Should -Be 0
		}

		It "resolves the separator and the color map from configuration" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{
				Onefetch = @{
					Style = @{
						Enabled   = $true
						Separator = " -> "
						Colors    = @{ "12" = "38;2;30;144;255" }
					}
				}
			}

			$settings.Onefetch.Style.Enabled | Should -BeTrue
			$settings.Onefetch.Style.Separator | Should -BeExactly " -> "
			$settings.Onefetch.Style.Colors["12"] | Should -BeExactly "38;2;30;144;255"
		}

		It "keeps a separator of nothing but spaces - it is a separator, not a value" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Onefetch = @{ Style = @{ Separator = "  " } } }

			$settings.Onefetch.Style.Separator | Should -BeExactly "  "
		}

		It "falls back to the defaults when Style is not a hashtable" {
			# Same degradation as every other branch: a malformed section is not an error at the
			# prompt.
			$style = (Resolve-TerminalGreetingSettings -Settings @{ Onefetch = @{ Style = "on" } }).Onefetch.Style

			$style.Enabled | Should -BeFalse
			$style.Separator | Should -BeNullOrEmpty
			$style.Colors.Count | Should -Be 0
		}

		It "ignores a Colors written as something other than a hashtable" {
			$style = (Resolve-TerminalGreetingSettings -Settings @{ Onefetch = @{ Style = @{ Colors = @("12") } } }).Onefetch.Style

			$style.Colors.Count | Should -Be 0
		}

		It "leaves an out-of-range index to Format-OnefetchPanel rather than warning here" {
			# The map is free-form on purpose - the consumer skips what it cannot use and says so
			# at debug level, which is the right place for a hand-written psd1.
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Onefetch = @{ Style = @{ Colors = @{ "33" = "38;2;1;2;3" } } } }

			$settings.Onefetch.Style.Colors["33"] | Should -BeExactly "38;2;1;2;3"
			Should -Invoke Write-LogWarning -Times 0 -Exactly
		}
	}

	Context "values out of range" {
		It "warns and uses the default for a non-integer MaxShrinkSteps" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Fastfetch = @{ AutoFit = @{ MaxShrinkSteps = "many" } } }

			$settings.Fastfetch.AutoFit.MaxShrinkSteps | Should -Be 10
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter {
				$Message -like "*TerminalGreeting.Fastfetch.AutoFit.MaxShrinkSteps must be an integer between 0 and 50*"
			}
		}

		It "warns and uses the default for <Path> = <Value>" -ForEach @(
			@{ Path = "MaxShrinkSteps"; Value = 51; Default = 10 }
			@{ Path = "MaxShrinkSteps"; Value = -1; Default = 10 }
			@{ Path = "ReflowTimeoutMilliseconds"; Value = 0; Default = 10 }
			@{ Path = "PromptReserve"; Value = 21; Default = 1 }
		) {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Fastfetch = @{ AutoFit = @{ $Path = $Value } } }

			$settings.Fastfetch.AutoFit.$Path | Should -Be $Default
			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}

		It "accepts any positive ReflowTimeoutMilliseconds, however large - it is the tuning knob" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Fastfetch = @{ AutoFit = @{ ReflowTimeoutMilliseconds = 100000 } } }

			$settings.Fastfetch.AutoFit.ReflowTimeoutMilliseconds | Should -Be 100000
			Should -Invoke Write-LogWarning -Times 0 -Exactly
		}

		It "warns about an out-of-range parameter and keeps the configured value" {
			$settings = Resolve-TerminalGreetingSettings -Settings @{ Fastfetch = @{ AutoFit = @{ MaxShrinkSteps = 3 } } } -MaxShrinkSteps 99

			$settings.Fastfetch.AutoFit.MaxShrinkSteps | Should -Be 3
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "-MaxShrinkSteps must be*" }
		}
	}
}
