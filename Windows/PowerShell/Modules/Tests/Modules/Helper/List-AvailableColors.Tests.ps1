#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\List-AvailableColors.ps1"
}

Describe "List-AvailableColors" {
	BeforeEach {
		Mock Write-Host { }
	}

	It "writes color matrix output" {
		{ List-AvailableColors } | Should -Not -Throw
	}
}
