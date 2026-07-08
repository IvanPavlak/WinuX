#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-RiseupVPN.ps1"
}

Describe "Open-RiseupVPN" {
	BeforeEach {
		Mock Start-Application { }
	}

	It "delegates to Start-Application using configured Riseup VPN executable and NoNewWindow" {
		Open-RiseupVPN

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'RiseupVPN' -and
			$ProcessName -eq 'riseup-vpn' -and
			$StartMethod -eq 'ConfigPath' -and
			$ConfigKey -eq 'RiseupVpnExe' -and
			$NoNewWindow
		}
	}
}
