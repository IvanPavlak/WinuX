function Get-RepositoryHooksState {
	<#
	.SYNOPSIS
		Reads the record of every core.hooksPath Sync-RepositoryHooks wrote on this machine.

	.DESCRIPTION
		Sync-RepositoryHooks turns a repository's tracked git hooks on by writing
		`core.hooksPath` into the clone's local git configuration, and may only ever take back a
		value it wrote itself. What it wrote is recorded in
		%LOCALAPPDATA%\WinuX\repository-hooks.state: one `<repository path><TAB><hooks folder>`
		line per clone, below a comment line. This function reads that file; it never writes it.

		A missing file, a comment line, a blank line and a line without a tab all read as
		"nothing recorded". Paths are compared without case, as Windows does.

	.OUTPUTS
		[pscustomobject] with Path (the state file, whether or not it exists) and Entries (a
		hashtable: repository path to the hooks folder written there).

	.EXAMPLE
		(Get-RepositoryHooksState).Entries
		Every clone whose core.hooksPath this machine's repository update wrote, with the value.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param()

	$localAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
	$statePath = Join-Path $localAppData 'WinuX\repository-hooks.state'

	# A PowerShell hashtable literal compares its keys without case, which is what a Windows path needs.
	$entries = @{}
	if (Test-Path -LiteralPath $statePath -PathType Leaf) {
		foreach ($line in [IO.File]::ReadAllLines($statePath)) {
			if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
			$parts = $line -split "`t", 2
			if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) { continue }
			$entries[$parts[0]] = $parts[1]
		}
	}

	return [pscustomobject]@{
		Path    = $statePath
		Entries = $entries
	}
}
