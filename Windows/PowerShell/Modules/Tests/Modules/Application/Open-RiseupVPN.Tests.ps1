#Requires -Modules Pester

BeforeAll {
	# Deprecated since 2.17.0: count no once-per-session deprecation warning in these tests, and
	# put back the flags this file found.
	$script:SavedDeprecationWarned = $global:WinuXDeprecationWarned
	$global:WinuXDeprecationWarned = @{ 'Open-LeagueOfLegends' = $true; 'Open-FoundryVTT' = $true; 'Open-RiseupVPN' = $true; 'Open-SecureBrowser' = $true; 'Open-DnD' = $true; 'Open-Training' = $true; 'Training-Backup' = $true; 'Test-PrivacyStatus' = $true; 'Invoke-PrivacyRequest' = $true; 'Invoke-TorRequest' = $true; 'Clear-WhatsAppLocalStorage' = $true; 'Configure-PostgreSqlPasswords' = $true }

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-RiseupVPN.ps1"
}

AfterAll {
	$global:WinuXDeprecationWarned = $script:SavedDeprecationWarned
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

	Context "deprecation warning" {
		BeforeEach {
			Mock Write-LogWarning { }
		}

		It "warns once per session, however often it is called" {
			$global:WinuXDeprecationWarned = $null

			Open-RiseupVPN
			Open-RiseupVPN

			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*deprecated since 2.17.0*3.0.0*' }
			Should -Invoke Start-Application -Times 2 -Exactly
		}

		It "keeps the flags other deprecated functions set" {
			$global:WinuXDeprecationWarned = @{ 'Open-DnD' = $true }

			Open-RiseupVPN

			$global:WinuXDeprecationWarned['Open-DnD'] | Should -BeTrue
			$global:WinuXDeprecationWarned['Open-RiseupVPN'] | Should -BeTrue
		}
	}
}
