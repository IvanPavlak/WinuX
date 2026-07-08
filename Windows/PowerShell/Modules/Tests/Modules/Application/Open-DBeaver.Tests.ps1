#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-DBeaver.ps1"
}

Describe "Open-DBeaver" {
	BeforeEach {
		Mock Start-Application { }
	}

	It "delegates to Start-Application with DBeaver config path and NoNewWindow" {
		Open-DBeaver

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'DBeaver' -and
			$ProcessName -eq 'dbeaver' -and
			$StartMethod -eq 'ConfigPath' -and
			$ConfigKey -eq 'DbeaverExe' -and
			$NoNewWindow
		}
	}
}
