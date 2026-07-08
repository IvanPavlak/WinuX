#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Open-DnD.ps1"
}

Describe "Open-DnD" {
	BeforeEach {
		$script:Configuration = @{
			Campaigns         = @("ExampleCampaign")
			CampaignResources = @{ ExampleCampaign = @{ Pdf = "ExampleCharacter"; Browser = "Reference" } }
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
