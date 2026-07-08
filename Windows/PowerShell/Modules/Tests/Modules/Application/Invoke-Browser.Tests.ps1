#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Invoke-Browser.ps1"
}

Describe "Invoke-Browser" {
	BeforeEach {
		Mock Open-Browser { }
	}

	It "joins query tokens and forwards them to Open-Browser -Search" {
		Invoke-Browser powershell hashtable

		Should -Invoke Open-Browser -Times 1 -Exactly -ParameterFilter {
			$Search -eq 'powershell hashtable'
		}
	}

	It "calls Open-Browser with an empty search string when no query is provided" {
		Invoke-Browser

		Should -Invoke Open-Browser -Times 1 -Exactly -ParameterFilter {
			$Search -eq ''
		}
	}
}
