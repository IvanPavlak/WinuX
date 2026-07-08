#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-FoundryVTT.ps1"
}

Describe "Open-FoundryVTT" {
	BeforeEach {
		Mock Start-Application { }
	}

	It "delegates to Start-Application with FoundryVTT config path and NoNewWindow" {
		Open-FoundryVTT

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'FoundryVTT' -and
			$ProcessName -eq 'Foundry Virtual Tabletop' -and
			$StartMethod -eq 'ConfigPath' -and
			$ConfigKey -eq 'FoundryVTTExe' -and
			$NoNewWindow
		}
	}
}
