#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-TeamViewer.ps1"
}

Describe "Open-TeamViewer" {
	BeforeEach {
		Mock Start-Application { }
	}

	It "delegates to Start-Application using TeamViewer config executable and NoNewWindow" {
		Open-TeamViewer

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'TeamViewer' -and
			$ProcessName -eq 'TeamViewer' -and
			$StartMethod -eq 'ConfigPath' -and
			$ConfigKey -eq 'TeamViewerExe' -and
			$NoNewWindow
		}
	}
}
