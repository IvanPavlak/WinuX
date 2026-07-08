#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Configure-PostgreSqlPasswords.ps1"
}

Describe "Configure-PostgreSqlPasswords" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			PostgreSqlPasswords = $null
		}
		Mock Test-Path { $false }
		Mock Custom-ReadHost { "value" }
		Mock Write-ManualInstructionsToDesktop { }
		Mock Write-Host { }
	}

	It "returns in auto mode when PostgreSqlPasswords configuration is missing" {
		{ Configure-PostgreSqlPasswords -Auto } | Should -Not -Throw

		Should -Invoke Custom-ReadHost -Times 0
		Should -Invoke Write-ManualInstructionsToDesktop -Times 0
	}
}
