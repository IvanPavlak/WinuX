#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	# The unconfigured-section guards warn through Confirm-ConfigValue (Helper);
	# dot-source it (and its Test-ConfigValue dependency) so the Write-LogWarning
	# mocks in these tests apply to the guard's warning.
	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"

	. "$FunctionsPath\Send-WakeOnLan.ps1"

	# Stub Resolve-Selection matching real signature (switch params for splatting compatibility)
	function Resolve-Selection {
		param(
			[string[]]$OptionList,
			[string[]]$InputObject,
			[string]$MenuTitle,
			[string]$PromptMessage,
			[switch]$AllowEmptyPromptResponse,
			[switch]$AllowMultipleSelections,
			$GroupsConfig
		)
		$InputObject
	}

	# Stub Test-MachineOnline (real function lives in its own file). Offline by default
	# so the default code path sends the packet; override with Mock per-test as needed.
	function Test-MachineOnline {
		param(
			[string]$Machine,
			[string]$Address,
			[string]$DisplayName,
			[switch]$WaitForOnline,
			[int]$TimeoutSeconds,
			[int]$IntervalSeconds,
			[int]$PingTimeoutMilliseconds,
			[switch]$Quiet
		)
		$false
	}
}

Describe "Send-WakeOnLan" {
	BeforeAll {
		$global:Configuration = @{
			WakeOnLanConfig         = @{
				"TestPC"     = @{
					MacAddress                     = "AA-BB-CC-DD-EE-FF"
					SubNetSpecificBroadcastAddress = "192.168.1.255"
					Address                        = "192.168.1.10"
					Port                           = 9
				}
				"TestServer" = @{
					MacAddress                     = "11:22:33:44:55:66"
					SubNetSpecificBroadcastAddress = "10.0.0.255"
					Address                        = "10.0.0.5"
					Port                           = 7
				}
			}
			WakeOnLanMachines       = @("TestPC", "TestServer", "All", "None")
			DefaultWakeOnLanMachine = "TestPC"
		}
	}

	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Test-MachineOnline { $false }
	}

	Context "When sending a WOL packet" {
		It "Should attempt to send WOL to the configured machine" {
			Send-WakeOnLan -Machine "TestPC"

			Should -Invoke Write-LogStep -ParameterFilter { $Message -match "Sending Wake-on-LAN" }
		}
	}

	Context "When the machine is already online" {
		It "Should skip the WOL packet" {
			Mock Test-MachineOnline { $true }

			Send-WakeOnLan -Machine "TestPC"

			Should -Invoke Write-LogSuccess -ParameterFilter { $Message -match "already online" }
			Should -Invoke Write-LogStep -Times 0 -ParameterFilter { $Message -match "Sending Wake-on-LAN" }
		}
	}

	Context "When -NoWait is specified" {
		It "Should send without pinging or verifying" {
			Send-WakeOnLan -Machine "TestPC" -NoWait

			Should -Invoke Write-LogStep -ParameterFilter { $Message -match "Sending Wake-on-LAN" }
			Should -Invoke Test-MachineOnline -Times 0
		}
	}

	Context "When machine is not in configuration" {
		It "Should show error for unknown machine" {
			Send-WakeOnLan -Machine "UnknownPC"

			Should -Invoke Write-LogError -ParameterFilter { $Message -match "not found" }
		}
	}

	Context "When None is selected" {
		It "Should cancel without sending" {
			Mock Resolve-Selection { @("None") }

			Send-WakeOnLan

			Should -Invoke Write-LogWarning -ParameterFilter { $Message -match "cancelled" }
		}
	}

	Context "When Wake-on-LAN is not configured (empty base)" {
		It "Should warn and send nothing when WakeOnLanConfig is an empty hashtable" {
			# @{} is truthy in PowerShell - this is exactly the case a bare -not guard misses.
			$global:Configuration = @{
				WakeOnLanConfig         = @{}
				WakeOnLanMachines       = @()
				DefaultWakeOnLanMachine = ""
			}
			Mock Resolve-Selection { }

			Send-WakeOnLan

			Should -Invoke Write-LogWarning -ParameterFilter { $Message -match "Wake-on-LAN not configured" }
			Should -Invoke Resolve-Selection -Times 0
			Should -Invoke Write-LogStep -Times 0 -ParameterFilter { $Message -match "Sending Wake-on-LAN" }
		}
	}

	AfterAll {
		Remove-Variable -Name Configuration -Scope Global -ErrorAction SilentlyContinue
	}
}
