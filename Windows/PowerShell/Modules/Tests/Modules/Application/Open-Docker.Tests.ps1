#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-Docker.ps1"
}

Describe "Open-Docker" {
	BeforeEach {
		Mock Start-Application { }
	}

	It "delegates to Start-Application with Docker Desktop config-path launch parameters" {
		Open-Docker

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'Docker Desktop' -and
			$ProcessName -eq 'Docker Desktop' -and
			$StartMethod -eq 'ConfigPath' -and
			$ConfigKey -eq 'DockerExe' -and
			$Arguments -eq '--minimized' -and
			$SuppressOutput
		}
	}
}
