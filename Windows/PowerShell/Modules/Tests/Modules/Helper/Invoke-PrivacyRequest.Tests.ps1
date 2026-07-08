#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Invoke-PrivacyRequest.ps1"
}

Describe "Invoke-PrivacyRequest" {
	BeforeEach {
		Mock Invoke-TorRequest { @{ mode = "tor" } }
		Mock Invoke-RestMethod { @{ mode = "direct" } }
	}

	It "routes through Tor helper when UseTor is specified" {
		$result = Invoke-PrivacyRequest -Uri "https://example" -UseTor

		$result.mode | Should -Be "tor"
		Should -Invoke Invoke-TorRequest -Times 1
	}

	It "uses direct request when UseTor is not specified" {
		$result = Invoke-PrivacyRequest -Uri "https://example"

		$result.mode | Should -Be "direct"
		Should -Invoke Invoke-RestMethod -Times 1
	}
}
