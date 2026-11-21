#Requires -Modules Pester

BeforeAll {
	# Deprecated since 2.17.0: count no once-per-session deprecation warning in these tests, and
	# put back the flags this file found.
	$script:SavedDeprecationWarned = $global:WinuXDeprecationWarned
	$global:WinuXDeprecationWarned = @{ 'Open-LeagueOfLegends' = $true; 'Open-FoundryVTT' = $true; 'Open-RiseupVPN' = $true; 'Open-SecureBrowser' = $true; 'Open-DnD' = $true; 'Open-Training' = $true; 'Training-Backup' = $true; 'Test-PrivacyStatus' = $true; 'Invoke-PrivacyRequest' = $true; 'Invoke-TorRequest' = $true; 'Clear-WhatsAppLocalStorage' = $true; 'Configure-PostgreSqlPasswords' = $true }

	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Configure-PostgreSqlPasswords.ps1"
}

AfterAll {
	$global:WinuXDeprecationWarned = $script:SavedDeprecationWarned
}

Describe "Configure-PostgreSqlPasswords" {
	BeforeEach {
		$global:Configuration = [PSCustomObject]@{
			PostgreSqlPasswords = $null
		}
		Mock Test-Path { $false }
		Mock Custom-ReadHost { "value" }
		Mock Write-ManualInstructionsToDesktop { }
		Mock Write-Host { }
	}

	It "returns in auto mode when PostgreSqlPasswords configuration is missing" {
		{ Configure-PostgreSqlPasswords -Auto } | Should -Not -Throw

		Should -Invoke Custom-ReadHost -Times 0
		Should -Invoke Write-ManualInstructionsToDesktop -Times 0
	}
}
