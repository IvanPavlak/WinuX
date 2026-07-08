#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\DotnetPublish.ps1"
}

Describe "DotnetPublish" {
	BeforeEach {
		Mock Find-Item { $null }
		Mock Write-Host { }
	}

	It "returns when no solution file is found" {
		{ DotnetPublish } | Should -Not -Throw
		Should -Invoke Find-Item -Times 1
	}
}
