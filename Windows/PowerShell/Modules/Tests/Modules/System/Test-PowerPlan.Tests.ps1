#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Test-PowerPlan.ps1"
	. "$FunctionsPath\Get-ChassisType.ps1"
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
		Mock Write-LogDebug { }
		$script:cache = Join-Path $TestDrive "ChassisTypes.txt"
	}

	Context "On a desktop PC" {
		It "Should not warn when Ultimate Performance is active" {
			Mock powercfg { "Power Scheme GUID: xxx  (Ultimate performance)" }
			Mock Get-ChassisType { [int[]]@(3) }

			Test-PowerPlan -CachePath $script:cache

			Should -Invoke Write-LogWarning -Times 0
		}

		It "Should warn when not on Ultimate Performance" {
			Mock powercfg { "Power Scheme GUID: xxx  (Balanced)" }
			Mock Get-ChassisType { [int[]]@(3) }

			Test-PowerPlan -CachePath $script:cache

			Should -Invoke Write-LogWarning -ParameterFilter { $Message -match "Ultimate Performance" }
		}
	}

	Context "On a laptop" {
		It "Should not warn when High Performance is active" {
			Mock powercfg { "Power Scheme GUID: xxx  (High performance)" }
			Mock Get-ChassisType { [int[]]@(9) }

			Test-PowerPlan -CachePath $script:cache

			Should -Invoke Write-LogWarning -Times 0
		}

		It "Should warn when not on High Performance" {
			Mock powercfg { "Power Scheme GUID: xxx  (Balanced)" }
			Mock Get-ChassisType { [int[]]@(10) }

			Test-PowerPlan -CachePath $script:cache

			Should -Invoke Write-LogWarning -ParameterFilter { $Message -match "High Performance" }
		}
	}

	Context "Chassis cache" {
		It "Reads the chassis type through Get-ChassisType with the cache path, without -Refresh by default" {
			Mock powercfg { "Power Scheme GUID: xxx  (Ultimate performance)" }
			Mock Get-ChassisType { [int[]]@(3) }

			Test-PowerPlan -CachePath $script:cache

			Should -Invoke Get-ChassisType -Times 1 -ParameterFilter { $CachePath -eq $script:cache -and -not $Refresh }
		}

		It "Passes -Refresh through so the hardware is queried again" {
			Mock powercfg { "Power Scheme GUID: xxx  (Ultimate performance)" }
			Mock Get-ChassisType { [int[]]@(3) }

			Test-PowerPlan -Refresh -CachePath $script:cache

			Should -Invoke Get-ChassisType -Times 1 -ParameterFilter { [bool]$Refresh }
		}

		It "Treats a machine with no chassis answer as a desktop" {
			Mock powercfg { "Power Scheme GUID: xxx  (High performance)" }
			Mock Get-ChassisType { [int[]]@() }

			Test-PowerPlan -CachePath $script:cache

			Should -Invoke Write-LogWarning -ParameterFilter { $Message -match "Ultimate Performance" }
		}
	}

	Context "Error handling" {
		It "Should catch and display errors gracefully" {
			Mock powercfg { throw "powercfg not available" }
			Mock Write-LogError { }

			{ Test-PowerPlan -CachePath $script:cache } | Should -Not -Throw

			Should -Invoke Write-LogError -ParameterFilter { $Message -match "Failed to check power plan" }
		}

		It "Reports a failed chassis query instead of throwing" {
			Mock powercfg { "Power Scheme GUID: xxx  (Balanced)" }
			Mock Get-ChassisType { throw "WMI unavailable" }
			Mock Write-LogError { }

			{ Test-PowerPlan -CachePath $script:cache } | Should -Not -Throw

			Should -Invoke Write-LogError -ParameterFilter { $Message -match "Failed to check power plan" }
		}
	}

	AfterAll {
		Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
	}
}
