#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Rename-Machine.ps1"
}

Describe "Rename-Machine" {
	BeforeEach {
		$env:COMPUTERNAME = "PC-HOST"
		$global:Configuration = [PSCustomObject]@{
			HostnameToMachineType = [ordered]@{
				"PC-HOST" = "PC"
			}
		}

		Mock Test-AdminPrivileges { }
		Mock Resolve-Selection { "No" }
		Mock Custom-ReadHost { "" }
		Mock Rename-Computer { }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogWarning { }
	}

	It "returns when hostname is already configured and override is not set" {
		{ Rename-Machine } | Should -Not -Throw
		Should -Invoke Resolve-Selection -Times 0
		Should -Invoke Rename-Computer -Times 0
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogWarning -Times 1
	}
}
