#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Clear-TaskbarPins.ps1"
}

Describe "Clear-TaskbarPins" {
	BeforeEach {
		Mock Test-AdminPrivileges { }
		Mock Test-Path { $false }
		Mock Restart-Explorer { }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogWarning { }
	}

	It "returns when Taskband registry path does not exist" {
		{ Clear-TaskbarPins } | Should -Not -Throw

		Should -Invoke Restart-Explorer -Times 0
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogWarning -Times 1
	}
}
