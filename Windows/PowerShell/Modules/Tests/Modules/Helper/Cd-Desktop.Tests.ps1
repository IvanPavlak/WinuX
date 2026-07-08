#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Cd-Desktop.ps1"
}

Describe "Cd-Desktop" {
	BeforeEach {
		Mock Set-Location { }
	}

	It "navigates to desktop folder path" {
		Cd-Desktop

		Should -Invoke Set-Location -Times 1
	}
}
