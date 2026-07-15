#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Unpin-TaskbarApps.ps1"
}

Describe "Unpin-TaskbarApps" {
	BeforeEach {
		$script:MachineSpecificPaths = [PSCustomObject]@{
			TaskbarLayoutFile = $null
		}
		Mock Test-AdminPrivileges { }
		Mock Clear-TaskbarPins { }
		Mock Write-Host { }
	}

	It "returns when TaskbarLayoutFile is missing" {
		{ Unpin-TaskbarApps } | Should -Not -Throw
		Should -Invoke Clear-TaskbarPins -Times 1
	}
}
