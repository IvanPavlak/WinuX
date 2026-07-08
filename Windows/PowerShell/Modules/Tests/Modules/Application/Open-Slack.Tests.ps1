#Requires -Modules Pester

BeforeAll {
	$script:OriginalLocalAppData = $env:LOCALAPPDATA
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-Slack.ps1"
}

AfterAll {
	$env:LOCALAPPDATA = $script:OriginalLocalAppData
}

Describe "Open-Slack" {
	BeforeEach {
		$env:LOCALAPPDATA = 'C:\Users\You\AppData\Local'
		Mock Start-Application { }
	}

	It "delegates to Start-Application with Slack direct path and processStart arguments" {
		Open-Slack

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'Slack' -and
			$ProcessName -eq 'slack' -and
			$StartMethod -eq 'DirectPath' -and
			$ExecutablePath -eq 'C:\Users\You\AppData\Local\slack\slack.exe' -and
			$Arguments -contains '--processStart' -and
			$Arguments -contains 'slack.exe'
		}
	}
}
