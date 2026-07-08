#Requires -Modules Pester

BeforeAll {
	$script:OriginalLocalAppData = $env:LOCALAPPDATA
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-Discord.ps1"
}

AfterAll {
	$env:LOCALAPPDATA = $script:OriginalLocalAppData
}

Describe "Open-Discord" {
	BeforeEach {
		$env:LOCALAPPDATA = 'C:\Users\You\AppData\Local'
		Mock Start-Application { }
	}

	It "delegates to Start-Application with Discord updater executable and NoNewWindow" {
		Open-Discord

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'Discord' -and
			$ProcessName -eq 'Discord' -and
			$StartMethod -eq 'DirectPath' -and
			$ExecutablePath -eq 'C:\Users\You\AppData\Local\Discord\Update.exe' -and
			$Arguments -contains '--processStart' -and
			$Arguments -contains 'Discord.exe' -and
			$NoNewWindow
		}
	}
}
