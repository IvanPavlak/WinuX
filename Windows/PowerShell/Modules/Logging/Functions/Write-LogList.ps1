function Write-LogList {
	<#
	.SYNOPSIS
		Writes a bulleted list of items, each on its own line beneath a preceding summary line.

	.DESCRIPTION
		Renders each item as "  • <item>" in the Step style (White) with no leading blank line, so the
		list sits directly under a summary written just before it (for example a Write-LogSuccess line).
		Empty or whitespace-only items are skipped. This is the shared renderer for the repository's
		"summary + bulleted detail" output (centered/moved windows, opened browser subgroups, and so on).

	.PARAMETER Items
		The list entries to render. Accepts an array or pipeline input.

	.EXAMPLE
		Write-LogSuccess "Centered 2 window(s)!"
		Write-LogList @("Windows Terminal", "Firefox")

		Renders:
		=> Centered 2 window(s)!
		  • Windows Terminal
		  • Firefox
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
		[AllowNull()]
		[string[]]$Items
	)

	process {
		foreach ($item in $Items) {
			if (-not [string]::IsNullOrWhiteSpace($item)) {
				Write-LogStep "  • $item" -NoLeadingNewline
			}
		}
	}
}
