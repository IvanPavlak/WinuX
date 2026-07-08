#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Set-CustomExecutionPolicy.ps1"
}

Describe "Set-CustomExecutionPolicy" {
	BeforeEach {
		Mock Write-Host { }
		Mock Set-ExecutionPolicy { }
	}

	It "sets execution policy to Bypass for the selected scope" {
		Set-CustomExecutionPolicy -Scope CurrentUser

		Should -Invoke Set-ExecutionPolicy -Times 1 -ParameterFilter { $ExecutionPolicy -eq "Bypass" -and $Scope -eq "CurrentUser" -and $Force }
	}
}
