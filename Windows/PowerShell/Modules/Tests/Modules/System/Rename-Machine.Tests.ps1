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

	It "renames with the typed name and no credential prompt" {
		# -LocalCredential used to receive the user name as a string, which made Rename-Computer
		# prompt for a credential before every rename.
		Mock Resolve-Selection { "Enter new name" }
		Mock Custom-ReadHost { "NEW-NAME" }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogError { }

		Rename-Machine -Override

		Should -Invoke Rename-Computer -Times 1 -Exactly -ParameterFilter {
			$NewName -eq "NEW-NAME" -and $null -eq $LocalCredential
		}
		Should -Invoke Write-LogError -Times 0
	}
}
