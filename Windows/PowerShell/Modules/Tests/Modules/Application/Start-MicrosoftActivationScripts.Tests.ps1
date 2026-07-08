#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Start-MicrosoftActivationScripts.ps1"
}

Describe "Start-MicrosoftActivationScripts" {
	BeforeEach {
		Mock Write-Host { }
		Mock Resolve-Selection { 'No' }
		Mock cscript { 'The machine is permanently activated.' }
		Mock Get-ItemProperty {
			[PSCustomObject]@{ 'Excel.Application.16' = 'dummy' }
		}
	}

	It "returns early without prompt when Windows is activated and Office is installed" {
		Start-MicrosoftActivationScripts

		Should -Invoke Resolve-Selection -Times 0
	}

	It "prompts and exits when Override is set and selection resolves to No" {
		Start-MicrosoftActivationScripts -Override

		Should -Invoke Resolve-Selection -Times 1 -Exactly
	}
}
