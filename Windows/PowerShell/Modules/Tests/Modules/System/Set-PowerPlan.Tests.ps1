#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

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
}
