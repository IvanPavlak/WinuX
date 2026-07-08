#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Test-PowerPlan.ps1"
}

Describe "Test-PowerPlan" {
	BeforeAll {
		$global:Configuration = @{
			LaptopChassisTypes = @(8, 9, 10, 14)
		}
	}

	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogWarning { }
	}

	Context "On a desktop PC" {
		It "Should not warn when Ultimate Performance is active" {
			Mock powercfg { "Power Scheme GUID: xxx  (Ultimate performance)" }
			Mock Get-CimInstance { [PSCustomObject]@{ ChassisTypes = @(3) } }

			Test-PowerPlan

			Should -Invoke Write-Host -Times 0 -ParameterFilter { $ForegroundColor -eq "Yellow" }
		}

		It "Should warn when not on Ultimate Performance" {
			Mock powercfg { "Power Scheme GUID: xxx  (Balanced)" }
			Mock Get-CimInstance { [PSCustomObject]@{ ChassisTypes = @(3) } }

			Test-PowerPlan

			Should -Invoke Write-LogWarning -ParameterFilter { $Message -match "Ultimate Performance" }
		}
	}

	Context "On a laptop" {
		It "Should not warn when High Performance is active" {
			Mock powercfg { "Power Scheme GUID: xxx  (High performance)" }
			Mock Get-CimInstance { [PSCustomObject]@{ ChassisTypes = @(9) } }

			Test-PowerPlan

			Should -Invoke Write-Host -Times 0 -ParameterFilter { $ForegroundColor -eq "Yellow" }
		}

		It "Should warn when not on High Performance" {
			Mock powercfg { "Power Scheme GUID: xxx  (Balanced)" }
			Mock Get-CimInstance { [PSCustomObject]@{ ChassisTypes = @(10) } }

			Test-PowerPlan

			Should -Invoke Write-LogWarning -ParameterFilter { $Message -match "High Performance" }
		}
	}

	Context "Error handling" {
		It "Should catch and display errors gracefully" {
			Mock powercfg { throw "powercfg not available" }
			Mock Write-LogError { }

			{ Test-PowerPlan } | Should -Not -Throw

			Should -Invoke Write-LogError -ParameterFilter { $Message -match "Failed to check power plan" }
		}
	}

	AfterAll {
		Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
	}
}
