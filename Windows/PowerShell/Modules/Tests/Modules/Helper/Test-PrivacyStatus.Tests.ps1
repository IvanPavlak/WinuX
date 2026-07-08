#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Test-PrivacyStatus.ps1"
}

Describe "Test-PrivacyStatus" {
	BeforeEach {
		Mock Write-Host { }
		Mock Get-Process { [PSCustomObject]@{ Name = "riseup-vpn" } }
		Mock Get-NetAdapter {
			[PSCustomObject]@{
				Status               = "Up"
				InterfaceDescription = "WireGuard Adapter"
				Name                 = "VPN Adapter"
				ifIndex              = 10
			}
		}
		Mock Get-NetRoute { [PSCustomObject]@{ InterfaceIndex = 10; NextHop = "0.0.0.0"; RouteMetric = 1 } } -ParameterFilter { $DestinationPrefix -eq "0.0.0.0/1" }
		Mock Get-NetRoute { [PSCustomObject]@{ InterfaceIndex = 10; NextHop = "0.0.0.0"; RouteMetric = 1 } } -ParameterFilter { $DestinationPrefix -eq "128.0.0.0/1" }

		Mock Invoke-PrivacyRequest { @{ ip = "2.2.2.2" } } -ParameterFilter { $Uri -eq "https://api.ipify.org?format=json" }
		Mock Invoke-PrivacyRequest {
			@{
				dns = @{
					ip  = @("9.9.9.9")
					geo = "Secure DNS"
				}
			}
		} -ParameterFilter { $Uri -eq "https://edns.ip-api.com/json" }
		Mock Invoke-PrivacyRequest {
			@{
				city       = "City"
				country    = "Country"
				connection = @{ isp = "Secure ISP" }
			}
		} -ParameterFilter { $Uri -eq "https://ipwho.is/" }
	}

	It "returns early in silent mode when checks are secure" {
		{ Test-PrivacyStatus -ISPIPAddress "1.1.1.1" -Silent } | Should -Not -Throw
		Should -Invoke Write-Host -Times 0
	}
}
