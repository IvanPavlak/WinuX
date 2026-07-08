#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-VirtualBox.ps1"
}

Describe "Open-VirtualBox" {
	BeforeEach {
		Mock Start-Application { }
	}

	It "delegates to Start-Application using VirtualBox config executable and NoNewWindow" {
		Open-VirtualBox

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'VirtualBox' -and
			$ProcessName -eq 'VirtualBox' -and
			$StartMethod -eq 'ConfigPath' -and
			$ConfigKey -eq 'VirtualBoxExe' -and
			$NoNewWindow
		}
	}
}
