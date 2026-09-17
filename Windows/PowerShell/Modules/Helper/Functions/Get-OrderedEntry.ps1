function Get-OrderedEntry {
	<#
	.SYNOPSIS
		Looks one entry up by name in an ordered configuration section.

	.DESCRIPTION
		The lookup counterpart of Get-OrderedNames: where that returns the menu, this returns
		the value the selected name carries. Both shapes are accepted - the ordered array of
		single-key hashtables, and, for a fork that has not migrated yet, a plain hashtable -
		so a consumer reads its entry the same way whichever shape the configuration has.

		Name matching is case-insensitive, and the first match wins, so a section that lists a
		name twice behaves like the file reads top to bottom. Returns $null when the section is
		empty or the name is not configured; the caller decides what an unconfigured entry means.

	.PARAMETER Section
		The configuration section to read. Accepts $null, an ordered array of single-key
		hashtables, or - legacy - a plain hashtable.

	.PARAMETER Name
		The entry name to look up.

	.EXAMPLE
		$workspaceActions = Get-OrderedEntry -Section $Configuration.WorkspaceActions -Name "WinuX"

	.EXAMPLE
		$resources = Get-OrderedEntry $Configuration.CampaignResources $Campaign
		if ($resources.Pdf) { Open-Acrobat -Pdf $resources.Pdf }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Position = 0)]
		[AllowNull()]
		$Section,

		[Parameter(Mandatory, Position = 1)]
		[string]$Name
	)

	if ($null -eq $Section -or [string]::IsNullOrWhiteSpace($Name)) {
		return $null
	}

	if ($Section -is [System.Collections.IDictionary]) {
		foreach ($key in $Section.Keys) {
			if ([string]$key -eq $Name) {
				return $Section[$key]
			}
		}
		return $null
	}

	foreach ($item in @($Section)) {
		if ($item -isnot [System.Collections.IDictionary]) { continue }

		foreach ($key in $item.Keys) {
			if ([string]$key -eq $Name) {
				return $item[$key]
			}
		}
	}

	return $null
}
