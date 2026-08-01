#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	# Dot-sourced rather than mocked: the point of these cases is that the reset profile follows the
	# machine type Get-LayoutMachineType resolves, redirects included.
	. "$FunctionsPath\Get-LayoutMachineType.ps1"
	. "$FunctionsPath\Reset-Windows.ps1"
}

Describe "Reset-Windows" {
	BeforeEach {
		Mock DetermineMachineType { 'PC' }
		Mock Remove-VirtualDesktops { }
		Mock Move-Windows { }
		Mock Center-Windows { }
		Mock Focus-TerminalTab { }
		Mock Write-LogWarning { }
		Mock Write-Host { }

		$global:Configuration = @{
			ResetAllWindowsDefaults = @{
				PC      = @{ VirtualDesktop = 1; Monitor = "2" }
				Laptop  = @{ VirtualDesktop = 1; Monitor = "" }
				Temp    = @{ VirtualDesktop = 2; Monitor = "Primary" }
				Default = @{ VirtualDesktop = 1; Monitor = "" }
			}
		}
	}

	Context "layout machine type redirects" {
		It "uses the override layout set's reset profile instead of the machine's own" {
			# The PC profile aims windows at monitor 2. On a borrowed single-monitor setup that
			# monitor does not exist, so the override has to select the profile too - otherwise the
			# layouts follow the override while the reset still targets absent hardware.
			$global:Configuration.LayoutMachineTypeOverrides = @{ PC = 'Temp' }

			Reset-Windows

			Should -Invoke Move-Windows -Times 1 -ParameterFilter { $VirtualDesktop -eq 2 -and $Monitor -eq "Primary" }
			Should -Invoke Center-Windows -Times 1 -ParameterFilter { $Monitor -eq "Primary" }
		}

		It "keeps the machine's own reset profile when the override entry is empty" {
			$global:Configuration.LayoutMachineTypeOverrides = @{ PC = '' }

			Reset-Windows

			Should -Invoke Move-Windows -Times 1 -ParameterFilter { $Monitor -eq "2" }
		}

		It "uses the small-display reset profile on a laptop-class primary display" {
			$global:Configuration.SmallDisplayMachineType = 'Laptop'
			Mock Get-MonitorInfo { @([PSCustomObject]@{ IsPrimary = $true; Width = 1920; Height = 1080 }) }

			Reset-Windows

			Should -Invoke Move-Windows -Times 1 -ParameterFilter { -not $Monitor }
		}

		It "still honours an explicit -Monitor over the redirected profile" {
			$global:Configuration.LayoutMachineTypeOverrides = @{ PC = 'Temp' }

			Reset-Windows -Monitor "Secondary"

			Should -Invoke Move-Windows -Times 1 -ParameterFilter { $Monitor -eq "Secondary" }
			Should -Invoke Center-Windows -Times 1 -ParameterFilter { $Monitor -eq "Secondary" }
		}
	}

	Context "monitor target propagation" {
		It "passes the configured monitor on to Center-Windows" {
			# The whole point of the fix: Center-Windows runs last, so it must re-assert the
			# intended monitor instead of re-deriving one from each window's current position.
			Reset-Windows

			Should -Invoke Move-Windows -Times 1 -ParameterFilter { $Monitor -eq "2" }
			Should -Invoke Center-Windows -Times 1 -ParameterFilter { $Monitor -eq "2" }
		}

		It "omits -Monitor for a machine configured without monitor targeting" {
			Mock DetermineMachineType { 'Laptop' }

			Reset-Windows

			Should -Invoke Center-Windows -Times 1 -ParameterFilter {
				-not $Monitor
			}
		}

		It "propagates an explicit -Monitor override to both passes" {
			Reset-Windows -Monitor "Primary"

			Should -Invoke Move-Windows -Times 1 -ParameterFilter { $Monitor -eq "Primary" }
			Should -Invoke Center-Windows -Times 1 -ParameterFilter { $Monitor -eq "Primary" }
		}

		It "skips monitor targeting entirely when -Monitor is an empty string" {
			Reset-Windows -Monitor ""

			Should -Invoke Move-Windows -Times 1 -ParameterFilter {
				-not $Monitor
			}
			Should -Invoke Center-Windows -Times 1 -ParameterFilter {
				-not $Monitor
			}
		}

		It "falls back to the Default entry for an unlisted machine type" {
			Mock DetermineMachineType { 'Work' }

			Reset-Windows

			Should -Invoke Move-Windows -Times 1 -ParameterFilter { $VirtualDesktop -eq 1 }
			Should -Invoke Center-Windows -Times 1 -ParameterFilter {
				-not $Monitor
			}
		}
	}

	Context "virtual desktop cleanup result" {
		It "warns and continues when the desktop collapse reports failure" {
			Mock Remove-VirtualDesktops { $false }

			Reset-Windows

			Should -Invoke Write-LogWarning -Times 1 -ParameterFilter {
				$Message -match 'Virtual desktop cleanup did not complete'
			}
			# The reset still runs: a partial collapse is reported, not fatal.
			Should -Invoke Move-Windows -Times 1
			Should -Invoke Center-Windows -Times 1
		}

		It "does not warn when the desktop collapse succeeds" {
			Reset-Windows

			Should -Invoke Write-LogWarning -Times 0 -ParameterFilter {
				$Message -match 'Virtual desktop cleanup did not complete'
			}
		}
	}

	It "runs the reset steps in order, ending with the terminal refocus" {
		Reset-Windows

		Should -Invoke Remove-VirtualDesktops -Times 1
		Should -Invoke Move-Windows -Times 1
		Should -Invoke Center-Windows -Times 1
		Should -Invoke Focus-TerminalTab -Times 1
	}
}
