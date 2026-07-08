#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Preview-LoadingSpinners.ps1"
}

Describe "Preview-LoadingSpinners" {
	BeforeEach {
		$global:Configuration = [PSCustomObject]@{}
		Mock Write-Host { }
	}

	It "returns when loading spinner configuration is missing" {
		{ Preview-LoadingSpinners } | Should -Not -Throw
		Should -Invoke Write-Host -Times 1
	}
}
