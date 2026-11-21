#Requires -Modules Pester

BeforeAll {
	# Deprecated since 2.17.0: count no once-per-session deprecation warning in these tests, and
	# put back the flags this file found.
	$script:SavedDeprecationWarned = $global:WinuXDeprecationWarned
	$global:WinuXDeprecationWarned = @{ 'Open-LeagueOfLegends' = $true; 'Open-FoundryVTT' = $true; 'Open-RiseupVPN' = $true; 'Open-SecureBrowser' = $true; 'Open-DnD' = $true; 'Open-Training' = $true; 'Training-Backup' = $true; 'Test-PrivacyStatus' = $true; 'Invoke-PrivacyRequest' = $true; 'Invoke-TorRequest' = $true; 'Clear-WhatsAppLocalStorage' = $true; 'Configure-PostgreSqlPasswords' = $true }

	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Clear-WhatsAppLocalStorage.ps1"
}

AfterAll {
	$global:WinuXDeprecationWarned = $script:SavedDeprecationWarned
}

Describe "Clear-WhatsAppLocalStorage" {
	BeforeEach {
		$global:Configuration = [PSCustomObject]@{
			Universal = [PSCustomObject]@{
				WhatsAppLocalStoragePath = "C:\\Temp\\WhatsAppStorage"
			}
		}

		Mock Test-AdminPrivileges { }
		Mock Get-Process { $null }
		Mock Stop-Process { }
		Mock Test-Path { $false }
		Mock Resolve-Selection { "Yes" }
		Mock Remove-Item { }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogWarning { }
	}

	It "returns early when storage path does not exist" {
		{ Clear-WhatsAppLocalStorage } | Should -Not -Throw
		Should -Invoke Resolve-Selection -Times 0
		Should -Invoke Remove-Item -Times 0
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogStep -Times 1
		Should -Invoke Write-LogWarning -Times 2
	}
}
