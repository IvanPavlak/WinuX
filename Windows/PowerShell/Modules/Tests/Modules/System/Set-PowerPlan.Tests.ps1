#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	# The unconfigured-section guards warn through Confirm-ConfigValue (Helper);
	# dot-source it (and its Test-ConfigValue dependency) so the Write-LogWarning
	# mocks in these tests apply to the guard's warning.
	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"

	. "$FunctionsPath\Set-PowerPlan.ps1"
}

Describe "Set-PowerPlan" {
	BeforeEach {
		Mock Test-AdminPrivileges { }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogWarning { }
		Mock Resolve-Selection { "Balanced" }
		Mock powercfg {
			if ($args[0] -eq "/getactivescheme") {
				"Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)"
			}
		}
	}

	It "returns early when selected mode is already active" {
		{ Set-PowerPlan -Mode "Balanced" } | Should -Not -Throw
		Should -Invoke powercfg -Times 1 -ParameterFilter { $args[0] -eq "/getactivescheme" }
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogWarning -Times 1
	}

	It "-Auto leaves the plan as-is when PowerPlans is empty (empty base, no Balanced fallback)" {
		$global:Configuration = [PSCustomObject]@{ PowerPlans = @{} }
		Mock DetermineMachineType { "PC" }
		Mock Write-LogStep { }

		{ Set-PowerPlan -Auto } | Should -Not -Throw

		Should -Invoke powercfg -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "No power plan configured" }
	}

	It "-Auto leaves the plan as-is when the machine type has no PowerPlans entry" {
		$global:Configuration = [PSCustomObject]@{ PowerPlans = @{ Laptop = "Balanced" } }
		Mock DetermineMachineType { "PC" }
		Mock Write-LogStep { }

		{ Set-PowerPlan -Auto } | Should -Not -Throw

		Should -Invoke powercfg -Times 0
	}

	Context "PowerTimeouts" {
		BeforeEach {
			Mock DetermineMachineType { "PC" }
			Mock Write-LogStep { }
			Mock Write-LogSuccess { }
			Mock powercfg {
				if ($args[0] -eq "/list") {
					"Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced) *"
					"Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)"
				}
				elseif ($args[0] -eq "/getactivescheme") {
					"Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)"
				}
			}
		}

		It "-Auto writes the configured timeouts into every scheme, in seconds, even with no plan configured" {
			$global:Configuration = @{ PowerPlans = @{}; PowerTimeouts = @{ PC = @{ SleepPluggedIn = 0; DisplayPluggedIn = 15 } } }

			Set-PowerPlan -Auto

			Should -Invoke powercfg -Times 2 -Exactly -ParameterFilter { $args[0] -eq "/SETACVALUEINDEX" -and $args[2] -eq "SUB_SLEEP" -and $args[3] -eq "STANDBYIDLE" -and $args[4] -eq 0 }
			Should -Invoke powercfg -Times 2 -Exactly -ParameterFilter { $args[0] -eq "/SETACVALUEINDEX" -and $args[2] -eq "SUB_VIDEO" -and $args[3] -eq "VIDEOIDLE" -and $args[4] -eq 900 }
			Should -Invoke powercfg -Times 0 -ParameterFilter { $args[0] -eq "/SETDCVALUEINDEX" } -Because "a timeout left out is not managed"
			Should -Invoke powercfg -Times 1 -Exactly -ParameterFilter { $args[0] -eq "/SETACTIVE" }
		}

		It "-Auto keeps applying the timeouts when the plan is already active" {
			$global:Configuration = @{ PowerPlans = @{ PC = "Balanced" }; PowerTimeouts = @{ PC = @{ HibernatePluggedIn = 0 } } }

			Set-PowerPlan -Auto

			Should -Invoke powercfg -Times 2 -Exactly -ParameterFilter { $args[0] -eq "/SETACVALUEINDEX" -and $args[3] -eq "HIBERNATEIDLE" }
		}

		It "skips an unknown key and a negative value with a warning, and touches no timeout without -Auto" {
			$global:Configuration = @{ PowerPlans = @{}; PowerTimeouts = @{ PC = @{ SleepSoon = 5; SleepOnBattery = -1 } } }

			Set-PowerPlan -Auto
			Should -Invoke powercfg -Times 0 -ParameterFilter { $args[0] -like "/SET*VALUEINDEX" }
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "*SleepSoon*" }

			Set-PowerPlan -Mode "Balanced"
			Should -Invoke powercfg -Times 0 -ParameterFilter { $args[0] -like "/SET*VALUEINDEX" }
		}
	}
}
