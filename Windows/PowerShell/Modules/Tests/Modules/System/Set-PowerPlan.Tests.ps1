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
		$script:Configuration = [PSCustomObject]@{ PowerPlans = @{} }
		Mock DetermineMachineType { "PC" }
		Mock Write-LogStep { }

		{ Set-PowerPlan -Auto } | Should -Not -Throw

		Should -Invoke powercfg -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "No power plan configured" }
	}

	It "-Auto leaves the plan as-is when the machine type has no PowerPlans entry" {
		$script:Configuration = [PSCustomObject]@{ PowerPlans = @{ Laptop = "Balanced" } }
		Mock DetermineMachineType { "PC" }
		Mock Write-LogStep { }

		{ Set-PowerPlan -Auto } | Should -Not -Throw

		Should -Invoke powercfg -Times 0
	}
}
