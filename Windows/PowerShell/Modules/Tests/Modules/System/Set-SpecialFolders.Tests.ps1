#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

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
	}

	It "returns when SpecialFolders configuration is missing" {
		{ Set-SpecialFolders } | Should -Not -Throw
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogError -Times 1
	}
}
