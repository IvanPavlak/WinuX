#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Invoke-TorRequest.ps1"
}

Describe "Invoke-TorRequest" {
	BeforeEach {
		Mock Start-Sleep { }
	}

	It "returns response when first Tor port succeeds" {
		Mock Invoke-RestMethod { @{ ok = $true } }

		$result = Invoke-TorRequest -Uri "https://api.example" -RetryCount 1

		$result.ok | Should -BeTrue
		Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Proxy -eq "socks5://127.0.0.1:9150" }
	}

	It "falls back to second Tor port when first port is unavailable" {
		$script:calls = @()
		Mock Invoke-RestMethod {
			param($Uri, $Proxy)
			$script:calls += $Proxy
			if ($Proxy -eq "socks5://127.0.0.1:9150") {
				throw ([System.Net.WebException]::new("Unable to connect to proxy"))
			}
			@{ source = "9050" }
		}

		$result = Invoke-TorRequest -Uri "https://api.example" -RetryCount 1

		$result.source | Should -Be "9050"
		$script:calls | Should -Contain "socks5://127.0.0.1:9150"
		$script:calls | Should -Contain "socks5://127.0.0.1:9050"
	}
}
