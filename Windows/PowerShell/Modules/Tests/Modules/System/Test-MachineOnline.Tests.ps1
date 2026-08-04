#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	# The unconfigured-section guards warn through Confirm-ConfigValue (Helper);
	# dot-source it (and its Test-ConfigValue dependency) so the Write-LogWarning
	# mocks in these tests apply to the guard's warning.
	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"

	. "$FunctionsPath\Test-MachineOnline.ps1"
}

Describe "Test-MachineOnline" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogError { }
		Mock Write-LogWarning { }
	}

	Context "When WakeOnLanConfig is missing" {
		It "Returns false and warns that Wake-on-LAN is not configured" {
			$global:Configuration = @{}

			Test-MachineOnline -Machine "Server" | Should -BeFalse
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -match "Wake-on-LAN not configured" }

			Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
		}

		It "Returns false when WakeOnLanConfig is an empty hashtable (truthy in PowerShell)" {
			$global:Configuration = @{ WakeOnLanConfig = @{} }

			Test-MachineOnline -Machine "Server" | Should -BeFalse
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -match "Wake-on-LAN not configured" }

			Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
		}
	}

	Context "When the machine is not configured" {
		It "Returns false and reports it was not found" {
			$global:Configuration = @{ WakeOnLanConfig = @{ "Server" = @{ Address = "10.0.0.5" } } }

			Test-MachineOnline -Machine "Unknown" | Should -BeFalse
			Should -Invoke Write-LogError -ParameterFilter { $Message -match "not found" }

			Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
		}
	}

	Context "When the machine has no Address" {
		It "Returns false and warns that reachability cannot be tested" {
			$global:Configuration = @{ WakeOnLanConfig = @{ "Server" = @{ Address = "" } } }

			Test-MachineOnline -Machine "Server" | Should -BeFalse
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -match "No \[Address\] configured" }

			Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
		}
	}

	Context "When -Quiet is specified on an unresolvable target" {
		It "Returns a boolean and writes nothing" {
			$global:Configuration = @{ WakeOnLanConfig = @{ "Server" = @{ Address = "" } } }

			$result = Test-MachineOnline -Machine "Server" -Quiet
			$result | Should -BeOfType [bool]
			$result | Should -BeFalse
			Should -Invoke Write-Host -Times 0
			Should -Invoke Write-LogWarning -Times 0
			Should -Invoke Write-LogError -Times 0

			Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
		}
	}
}
