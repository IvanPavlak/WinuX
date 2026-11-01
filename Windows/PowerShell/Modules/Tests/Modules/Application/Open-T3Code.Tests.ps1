#Requires -Modules Pester

BeforeAll {
	$script:OriginalLocalAppData = $env:LOCALAPPDATA
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-T3Code.ps1"
}

AfterAll {
	$env:LOCALAPPDATA = $script:OriginalLocalAppData
}

Describe "Open-T3Code" {
	BeforeEach {
		$env:LOCALAPPDATA = 'C:\Users\You\AppData\Local'
		Mock Start-Application { }
	}

	It "delegates to Start-Application with the per-user T3 Code executable, detached" {
		Open-T3Code

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'T3 Code' -and
			$ProcessName -eq 'T3 Code (Beta)' -and
			$StartMethod -eq 'DirectPath' -and
			$ExecutablePath -eq 'C:\Users\You\AppData\Local\Programs\t3code\T3 Code (Beta).exe' -and
			$Detached -eq $true
		}
	}
}
