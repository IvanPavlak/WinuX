#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Set-PowerButtonActions.ps1"
}

Describe "Set-PowerButtonActions" {
	BeforeEach {
		Mock Test-AdminPrivileges { }
		Mock powercfg {
			if ($args[0] -eq "/list") {
				@("No power schemes available")
			}
		}
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogError { }
	}

	It "returns when no power schemes are found" {
		{ Set-PowerButtonActions } | Should -Not -Throw

		Should -Invoke powercfg -Times 1 -ParameterFilter { $args[0] -eq "/list" }
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogError -Times 1
	}

	It "-Auto leaves power settings as-is when PowerButtonActions is empty (empty base, no hardcoded defaults)" {
		$script:Configuration = [PSCustomObject]@{ PowerButtonActions = @{} }
		Mock DetermineMachineType { "PC" }
		Mock Write-LogStep { }
		Mock Write-LogWarning { }

		{ Set-PowerButtonActions -Auto } | Should -Not -Throw

		Should -Invoke powercfg -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "PowerButtonActions not configured" }
	}
}
