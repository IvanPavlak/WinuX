#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	# The unconfigured-section guards warn through Confirm-ConfigValue (Helper);
	# dot-source it (and its Test-ConfigValue dependency) so the Write-LogWarning
	# mocks in these tests apply to the guard's warning.
	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"

	. "$FunctionsPath\Set-SpecialFolders.ps1"
}

Describe "Set-SpecialFolders" {
	BeforeEach {
		$global:MachineType = "PC"
		$global:Configuration = [PSCustomObject]@{
			SpecialFolders = $null
			BasePaths      = [ordered]@{
				PC = [PSCustomObject]@{ Dev = "C:\\Dev"; User = "C:\\Users\\You" }
			}
		}
		Mock Test-AdminPrivileges { }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogError { }
		Mock Write-LogWarning { }
	}

	It "returns with a warning when SpecialFolders configuration is missing" {
		{ Set-SpecialFolders } | Should -Not -Throw
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogError -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "SpecialFolders not configured" }
	}
}
