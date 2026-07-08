#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Set-EnvironmentVariables.ps1"
}

Describe "Set-EnvironmentVariables" {
	BeforeEach {
		$global:MachineType = "PC"
		$global:Configuration = [PSCustomObject]@{
			AutoEnvironmentVariables = $null
			BasePaths                = [ordered]@{
				PC = [PSCustomObject]@{ Dev = "C:\\Dev"; User = "C:\\Users\\You" }
			}
		}
		$script:Configuration = $global:Configuration

		Mock Test-AdminPrivileges { }
		Mock Expand-Hashtable { $Source }
		Mock Set-Item { }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogWarning { }
	}

	It "returns in auto mode when no automatic variables are configured" {
		{ Set-EnvironmentVariables -Auto } | Should -Not -Throw
		Should -Invoke Test-AdminPrivileges -Times 1
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogWarning -Times 1
	}

	It "returns in manual mode when Name or Value is missing" {
		{ Set-EnvironmentVariables -Name "MY_VAR" } | Should -Not -Throw
		Should -Invoke Test-AdminPrivileges -Times 1
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogWarning -Times 1
	}
}
