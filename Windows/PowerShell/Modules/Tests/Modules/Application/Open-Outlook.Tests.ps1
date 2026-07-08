#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-Outlook.ps1"
}

Describe "Open-Outlook" {
	BeforeEach {
		Mock Start-Application { }
	}

	It "delegates to Start-Application with Outlook config-path launch settings" {
		Open-Outlook

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'Outlook' -and
			$ProcessName -eq 'olk' -and
			$StartMethod -eq 'ConfigPath' -and
			$ConfigKey -eq 'OutlookLauncherExe' -and
			$Arguments -eq 'shell:AppsFolder\Microsoft.OutlookForWindows_8wekyb3d8bbwe!Microsoft.OutlookforWindows'
		}
	}
}
