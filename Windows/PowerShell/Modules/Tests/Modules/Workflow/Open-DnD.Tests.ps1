#Requires -Modules Pester

BeforeAll {
	# Deprecated since 2.17.0: count no once-per-session deprecation warning in these tests, and
	# put back the flags this file found.
	$script:SavedDeprecationWarned = $global:WinuXDeprecationWarned
	$global:WinuXDeprecationWarned = @{ 'Open-LeagueOfLegends' = $true; 'Open-FoundryVTT' = $true; 'Open-RiseupVPN' = $true; 'Open-SecureBrowser' = $true; 'Open-DnD' = $true; 'Open-Training' = $true; 'Training-Backup' = $true; 'Test-PrivacyStatus' = $true; 'Invoke-PrivacyRequest' = $true; 'Invoke-TorRequest' = $true; 'Clear-WhatsAppLocalStorage' = $true; 'Configure-PostgreSqlPasswords' = $true }

	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Open-DnD.ps1"
	. (Join-Path $ModuleRoot "Helper\Functions\Get-OrderedNames.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\Get-OrderedEntry.ps1")
}

AfterAll {
	$global:WinuXDeprecationWarned = $script:SavedDeprecationWarned
}

Describe "Open-DnD" {
	BeforeEach {
		$global:Configuration = @{
			CampaignResources = @(
				@{ ExampleCampaign = @{ Pdf = "ExampleCharacter"; Browser = "Reference" } }
			)
		}
		Mock Resolve-Selection { $null }
		Mock Open-FoundryVTT { }
		Mock Open-Obsidian { }
		Mock Open-Acrobat { }
		Mock Open-Browser { }
		Mock Write-Host { }
		Mock Write-LogWarning { }
	}

	It "returns when no campaign is selected" {
		Open-DnD

		Should -Invoke Open-Obsidian -Times 0
		Should -Invoke Write-LogWarning -Times 1
	}

	It "opens campaign resources for ExampleCampaign" {
		Mock Resolve-Selection { "ExampleCampaign" }

		Open-DnD

		Should -Invoke Open-Obsidian -Times 1
		Should -Invoke Open-Acrobat -Times 1 -ParameterFilter { $Pdf -eq "ExampleCharacter" }
		Should -Invoke Open-Browser -Times 1
	}

	It "starts FoundryVTT when switch is provided" {
		Mock Resolve-Selection { "ExampleCampaign" }

		Open-DnD -FoundryVTT

		Should -Invoke Open-FoundryVTT -Times 1
	}
}
