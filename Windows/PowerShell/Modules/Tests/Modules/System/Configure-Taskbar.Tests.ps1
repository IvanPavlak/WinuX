#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Configure-Taskbar.ps1"
	# Dot-source the machine-scope gate and machine-type resolver so both are mockable here,
	# regardless of whether the imported Bootstrap module in this session already exports them.
	. (Join-Path $ModuleRoot "Bootstrap\Functions\Test-MachineTypeScope.ps1")
	. (Join-Path $ModuleRoot "Bootstrap\Functions\DetermineMachineType.ps1")
}

Describe "Configure-Taskbar" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			Universal            = [PSCustomObject]@{ TaskbarPinFolder = "C:\\Temp\\TaskbarPins" }
			TaskbarConfiguration = $null
		}
		$global:MachineSpecificPaths = [PSCustomObject]@{
			TaskbarLayoutFile = "C:\\Temp\\taskbar_layout.xml"
		}

		Mock Test-AdminPrivileges { }
		Mock Unpin-TaskbarApps { }
		Mock Test-Path { $false }
		Mock Loading-Spinner { }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogError { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock DetermineMachineType { "Test" }
	}

	It "returns when TaskbarConfiguration is missing" {
		{ Configure-Taskbar } | Should -Not -Throw

		Should -Invoke Unpin-TaskbarApps -Times 1
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogStep -Times 1
		Should -Invoke Write-LogError -Times 1
	}

	Context "machine-type filtering" {
		BeforeEach {
			$script:Configuration.TaskbarConfiguration = @(
				@{ Name = "AllApp"; Type = "AUMID"; Value = "App.All"; Machine = "All" }
				@{ Name = "TestApp"; Type = "AUMID"; Value = "App.Test"; Machine = "Test" }
				@{ Name = "PcApp"; Type = "AUMID"; Value = "App.Pc"; Machine = "PC" }
				@{ Name = "UntaggedApp"; Type = "AUMID"; Value = "App.Untagged" }
			)

			# Write the layout XML into Pester's TestDrive so the generated pin list can be read
			# back, and stub the registry boundary. -FromBootstrap skips the lock/restart tail.
			$global:MachineSpecificPaths = [PSCustomObject]@{ TaskbarLayoutFile = (Join-Path "$TestDrive" "taskbar_layout.xml") }
			Mock New-Item { }
			Mock Set-ItemProperty { }
		}

		It "resolves the machine type and routes every row through Test-MachineTypeScope" {
			Mock Test-MachineTypeScope { $true }

			Configure-Taskbar -FromBootstrap

			Should -Invoke DetermineMachineType -Times 1
			Should -Invoke Test-MachineTypeScope -Times 4 -Exactly
		}

		It "defaults a row without a Machine key to the All scope" {
			Mock Test-MachineTypeScope { $true }

			Configure-Taskbar -FromBootstrap

			# Only the untagged row must be queried with the "All" fallback scope.
			Should -Invoke Test-MachineTypeScope -Times 1 -Exactly -ParameterFilter {
				$Scope -eq "All" -and $Context -eq "TaskbarConfiguration [UntaggedApp]"
			}
			# The tagged rows are queried with their own declared scope.
			Should -Invoke Test-MachineTypeScope -Times 1 -Exactly -ParameterFilter {
				$Scope -eq "PC" -and $Context -eq "TaskbarConfiguration [PcApp]"
			}
		}

		It "pins only rows whose Machine scope matches the current machine type" {
			# Simulate the gate: "All" or a scope naming the current machine type matches.
			Mock Test-MachineTypeScope {
				$Scope -eq "All" -or (($Scope -split "/" | ForEach-Object { $_.Trim() }) -contains $MachineType)
			}

			Configure-Taskbar -FromBootstrap

			# App.All ("All"), App.Test ("Test") and App.Untagged (defaulted to "All") match the
			# "Test" machine; App.Pc ("PC") does not and must be absent from the written layout.
			$layout = Get-Content -Path (Join-Path "$TestDrive" "taskbar_layout.xml") -Raw
			$layout | Should -Match "App\.All"
			$layout | Should -Match "App\.Test"
			$layout | Should -Match "App\.Untagged"
			$layout | Should -Not -Match "App\.Pc"
		}

		It "removes a pre-existing symlink at the layout path before writing" {
			Mock Test-MachineTypeScope { $true }
			# Simulate a leftover symlink from the old design sitting at the layout path.
			Mock Get-Item { [PSCustomObject]@{ LinkType = "SymbolicLink" } } -ParameterFilter { "$LiteralPath" -like "*taskbar_layout.xml" }
			Mock Remove-Item { }

			Configure-Taskbar -FromBootstrap

			Should -Invoke Remove-Item -Times 1 -Exactly -ParameterFilter { "$LiteralPath" -like "*taskbar_layout.xml" }
		}
	}
}
