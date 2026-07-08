#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Enable-DeveloperMode.ps1"
}

Describe "Enable-DeveloperMode" {
	BeforeEach {
		Mock Test-AdminPrivileges { }
		Mock Test-RegistryValue { $true }
		Mock Write-Host { }
	}

	It "returns through already-enabled path when registry indicates developer mode enabled" {
		{ Enable-DeveloperMode } | Should -Not -Throw
		Should -Invoke Test-AdminPrivileges -Times 1
		Should -Invoke Test-RegistryValue -Times 1
	}
}
