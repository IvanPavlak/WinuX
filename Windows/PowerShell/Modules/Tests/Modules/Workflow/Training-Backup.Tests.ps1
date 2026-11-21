#Requires -Modules Pester

BeforeAll {
	# Deprecated since 2.17.0: count no once-per-session deprecation warning in these tests, and
	# put back the flags this file found.
	$script:SavedDeprecationWarned = $global:WinuXDeprecationWarned
	$global:WinuXDeprecationWarned = @{ 'Open-LeagueOfLegends' = $true; 'Open-FoundryVTT' = $true; 'Open-RiseupVPN' = $true; 'Open-SecureBrowser' = $true; 'Open-DnD' = $true; 'Open-Training' = $true; 'Training-Backup' = $true; 'Test-PrivacyStatus' = $true; 'Invoke-PrivacyRequest' = $true; 'Invoke-TorRequest' = $true; 'Clear-WhatsAppLocalStorage' = $true; 'Configure-PostgreSqlPasswords' = $true }

	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Training-Backup.ps1"
}

AfterAll {
	$global:WinuXDeprecationWarned = $script:SavedDeprecationWarned
}

Describe "Training-Backup" {
	BeforeEach {
		Mock Set-Location { }
		Mock Write-Host { }
		Mock Write-LogSuccess { }
		Mock Write-LogError { }
	}

	It "runs backup script and restores original location" {
		Mock Get-Location { "C:\Start" }

		Training-Backup

		Should -Invoke Set-Location -Times 1
		Should -Invoke Write-LogError -Times 2
	}
}
