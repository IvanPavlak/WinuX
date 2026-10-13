function Open-DnD {
	<#
	.SYNOPSIS
		Opens the D&D campaign workspace: Obsidian vault, browser resources, and Acrobat rulebooks.

	.DESCRIPTION
		Opens all tools for a tabletop RPG session. The campaign is selected from the
		`CampaignResources` section of Configuration.psd1 (in its order) via an interactive
		menu if not specified.

		For the campaign, opens:
		- Obsidian (the vault with campaign notes)
		- Acrobat (the campaign's `Pdf`, an `AcrobatPdfGroups` name, via Open-Acrobat -Pdf)
		- Browser (the campaign's `Browser`, a `BrowserGroups` group, via Open-Browser)

		When `-FoundryVTT` is specified, the FoundryVTT game server is launched first -
		even when no campaign ends up selected.

	.PARAMETER Campaign
		Name of the campaign to open, as defined in the `CampaignResources` configuration list.
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

	$campaignResources = @(Get-ConfigSetting -Path 'CampaignResources' -Default @())

	$resolveParams = @{
		InputObject              = $Campaign
		OptionList               = @(Get-OrderedNames $campaignResources)
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

		# Per-campaign rulebook PDF group (AcrobatPdfGroups) and resource browser group
		# (BrowserGroups), driven from Configuration.CampaignResources - the one place a
		# campaign is defined, and the order the campaign menu above follows.
		$resources = Get-OrderedEntry $campaignResources $Campaign
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
