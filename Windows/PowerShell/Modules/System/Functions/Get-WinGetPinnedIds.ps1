function Get-WinGetPinnedIds {
	<#
	.SYNOPSIS
		Returns which of the given WinGet app IDs winget currently has a pin for, in one `winget pin list` call.

	.DESCRIPTION
		Reads every pin with a single `winget pin list` through `Invoke-PackageManagerCommand` and
		returns the IDs from -AppId that appear in it. Checking each app with its own call cost about a
		second per managed app; `winget pin list --id <app>` prints every pin anyway, so one call
		answers for all of them.

		The listing is a table whose columns shift with terminal width and the installed locale, so it
		is never parsed by column position. Each ID is matched as a whole whitespace-delimited token
		instead: "Git.Git" does not match a pin for "Git.GitLFS", and a mis-parse can never unpin the
		wrong app. An ID winget had to shorten to fit its column is not found, which leaves that pin in
		place - the safe direction.

		A call that stalls throws (see `Invoke-PackageManagerCommand`), so a stalled listing never
		reads as "no pins".

	.PARAMETER AppId
		The WinGet app IDs to look for.

	.OUTPUTS
		[string[]] The IDs from -AppId that winget has a pin for, in the order given.

	.EXAMPLE
		Get-WinGetPinnedIds -AppId "Git.Git", "Microsoft.PowerToys"
		Returns "Microsoft.PowerToys" when only PowerToys is pinned.
	#>
	[CmdletBinding()]
	[OutputType([string[]])]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[AllowEmptyCollection()]
		[string[]]$AppId
	)

	if ($AppId.Count -eq 0) { return }

	$pinLines = @(Invoke-PackageManagerCommand -PackageManager WinGet -Arguments 'pin', 'list', '--accept-source-agreements', '--disable-interactivity')

	foreach ($id in $AppId) {
		$token = "(?<!\S)$([regex]::Escape($id))(?!\S)"
		if ($pinLines | Where-Object { $_ -match $token }) { $id }
	}
}
