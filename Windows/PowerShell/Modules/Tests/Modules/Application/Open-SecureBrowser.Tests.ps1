#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-SecureBrowser.ps1"
}

Describe "Open-SecureBrowser" {
	BeforeEach {
		Mock Write-Host { }
		Mock Invoke-RestMethod { [PSCustomObject]@{ ip = '1.2.3.4' } }
		Mock Open-RiseupVPN { }
		Mock Resolve-Selection { }
		Mock Get-Process { $null }
		Mock Open-Browser { }
		Mock Loading-Spinner { }
		Mock Test-PrivacyStatus { }
	}

	It "runs VPN to Tor flow and verifies privacy status with retrieved ISP IP" {
		Open-SecureBrowser

		Should -Invoke Open-RiseupVPN -Times 1 -Exactly
		Should -Invoke Open-Browser -Times 1 -Exactly -ParameterFilter { $Browser -eq 'Tor' -and $NoMenu }
		Should -Invoke Test-PrivacyStatus -Times 1 -Exactly -ParameterFilter { $ISPIPAddress -eq '1.2.3.4' -and $UseTor }
	}
}
