function Get-OrderedNames {
	<#
	.SYNOPSIS
		Returns the entry names of an ordered configuration section, in configuration order.

	.DESCRIPTION
		The read side of the repository's one ordering rule: "order is where you write it".

		An ordered section is an array of single-key hashtables - the shape BrowserGroups and
		RepositoryGroups have always used - where each item's single key is the entry name and
		its value is the entry:

			WorkspaceActions = @(
				@{ Default = @( ... ) }
				@{ WinuX   = @( ... ) }
			)

		The section cannot be a plain hashtable, because Import-PowerShellDataFile returns a
		System.Collections.Hashtable and key order is lost at load time. Writing the entries in
		an array is what makes the menu order match the file, with no second name list to keep
		in sync.

		A plain hashtable is also accepted, so a fork that has not migrated its
		Configuration.local.psd1 keeps working. Its keys come back sorted - the load order is
		genuinely gone, so sorted is the only stable answer. Nothing is warned about here:
		Test-ConfigurationSchema is the one place that reports an ordered section written as a
		hashtable, once at load, instead of every menu saying it again.

	.PARAMETER Section
		The configuration section to read. Accepts $null (returns nothing), an ordered array of
		single-key hashtables, or a plain hashtable (sorted).

	.EXAMPLE
		Get-OrderedNames $Configuration.WorkspaceActions
		# Default, WinuX

	.EXAMPLE
		$resolveParams = @{
			OptionList = @(Get-OrderedNames $Configuration.CampaignResources)
		}
	#>
	[CmdletBinding()]
	[OutputType([string[]])]
	param(
		[Parameter(Position = 0)]
		[AllowNull()]
		$Section
	)

	if ($null -eq $Section) {
		return @()
	}

	if ($Section -is [System.Collections.IDictionary]) {
		return @($Section.Keys | ForEach-Object { [string]$_ } | Sort-Object)
	}

	$names = [System.Collections.ArrayList]::new()

	foreach ($item in @($Section)) {
		if ($item -is [System.Collections.IDictionary]) {
			foreach ($key in $item.Keys) {
				$names.Add([string]$key) | Out-Null
			}
		}
		elseif ($item -is [string] -and -not [string]::IsNullOrWhiteSpace($item)) {
			# A bare string entry names itself - lets a section carry entries that have no value.
			$names.Add($item) | Out-Null
		}
	}

	return @($names)
}
