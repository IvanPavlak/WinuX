#Requires -Modules Pester

BeforeAll {
	# Deprecated since 2.17.0: count no once-per-session deprecation warning in these tests, and
	# put back the flags this file found.
	$script:SavedDeprecationWarned = $global:WinuXDeprecationWarned
	$global:WinuXDeprecationWarned = @{ 'Open-LeagueOfLegends' = $true; 'Open-FoundryVTT' = $true; 'Open-RiseupVPN' = $true; 'Open-SecureBrowser' = $true; 'Open-DnD' = $true; 'Open-Training' = $true; 'Training-Backup' = $true; 'Test-PrivacyStatus' = $true; 'Invoke-PrivacyRequest' = $true; 'Invoke-TorRequest' = $true; 'Clear-WhatsAppLocalStorage' = $true; 'Configure-PostgreSqlPasswords' = $true }

	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Open-Training.ps1"
}

AfterAll {
	$global:WinuXDeprecationWarned = $script:SavedDeprecationWarned
}

Describe "Open-Training" {
	BeforeEach {
		$script:MachineSpecificPaths = @{ TrainingDirectory = "C:\Training" }
		$global:Configuration = @{ Universal = @{ TrainingFile = "Plan.docx" } }
		Mock Write-Host { }
		Mock Start-Process { }
	}

	It "starts Word process when not already running" {
		Mock Get-Process { $null } -ParameterFilter { $Name -eq "WINWORD" }

		Open-Training

		Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -eq "winword" }
	}

	It "does not start Word when already running" {
		Mock Get-Process { @{ Name = "WINWORD" } } -ParameterFilter { $Name -eq "WINWORD" }

		Open-Training

		Should -Invoke Start-Process -Times 0
	}
}
