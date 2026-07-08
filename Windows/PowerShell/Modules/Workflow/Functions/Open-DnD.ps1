function Open-DnD {
	<#
	.SYNOPSIS
		Opens the D&D campaign workspace: Obsidian vault, browser resources, and Acrobat rulebooks.

	.DESCRIPTION
		Opens all tools for a tabletop RPG session. The campaign is selected from the
		`Campaigns` section of Configuration.psd1 via an interactive menu if not specified.

		For each campaign, opens:
		- Obsidian (the vault with campaign notes)
		- Acrobat (rulebook PDF configured in `AcrobatGroups`)
		- Browser (spell/resource URLs configured in `BrowserGroups`)

		When `-FoundryVTT` is specified, also launches the FoundryVTT game server.

	.PARAMETER Campaign
		Name of the campaign to open, as defined in the `Campaigns` configuration array.
		Omit to show the interactive campaign selection menu.

	.PARAMETER FoundryVTT
		Also launches the FoundryVTT virtual tabletop server.

	.EXAMPLE
		Open-DnD
		Shows the campaign selection menu, then opens all campaign tools.

	.EXAMPLE
		Open-DnD -Campaign "ExampleCampaign" -FoundryVTT
		Opens the ExampleCampaign campaign with FoundryVTT.
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string]$Campaign,

		[Parameter()]
		[switch]$FoundryVTT = $false
	)

	$resolveParams = @{
		InputObject              = $Campaign
		OptionList               = $Configuration.Campaigns
		MenuTitle                = "[Available Campaigns]"
		AllowEmptyPromptResponse = $true
	}

	$Campaign = Resolve-Selection @resolveParams

	if ($FoundryVTT) {
		Open-FoundryVTT
	}

	if ([string]::IsNullOrWhiteSpace($Campaign)) {
		Write-LogWarning "No campaign selected!"
		return
	}

	try {
		Open-Obsidian

		# Map each campaign to its rulebook PDF group (AcrobatGroups) and browser
		# resource group (BrowserGroups). Add a case per entry in Campaigns.
		# Per-campaign rulebook PDF (AcrobatGroups) and resource browser group (BrowserGroups),
		# driven from Configuration.CampaignResources so personal campaign data lives only in config.
		$resources = $Configuration.CampaignResources.$Campaign
		if ($resources) {
			if ($resources.Pdf) { Open-Acrobat -Pdf $resources.Pdf }
			if ($resources.Browser) { Open-Browser $resources.Browser }
		}

		Write-LogSuccess "DnD Setup completed for $Campaign campaign!"
	}
	catch {
		Write-LogError "Error: $($_.Exception.Message)" -BlankLineAfter
	}
}
