#Requires -Modules Pester

BeforeAll {
	# Deprecated since 2.17.0: count no once-per-session deprecation warning in these tests, and
	# put back the flags this file found.
	$script:SavedDeprecationWarned = $global:WinuXDeprecationWarned
	$global:WinuXDeprecationWarned = @{ 'Open-LeagueOfLegends' = $true; 'Open-FoundryVTT' = $true; 'Open-RiseupVPN' = $true; 'Open-SecureBrowser' = $true; 'Open-DnD' = $true; 'Open-Training' = $true; 'Training-Backup' = $true; 'Test-PrivacyStatus' = $true; 'Invoke-PrivacyRequest' = $true; 'Invoke-TorRequest' = $true; 'Clear-WhatsAppLocalStorage' = $true; 'Configure-PostgreSqlPasswords' = $true }

	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Invoke-PrivacyRequest.ps1"
}

AfterAll {
	$global:WinuXDeprecationWarned = $script:SavedDeprecationWarned
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
