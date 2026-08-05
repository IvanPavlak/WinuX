function Get-WorkspaceState {
	<#
	.SYNOPSIS
		Reads the open-workspace tracker written by Save-WorkspaceState.

	.DESCRIPTION
		Open-Workspace records what each open actually produced - the windows that appeared and the
		Windows Terminal tabs that appeared - into Workflow\State\OpenWorkspaces.txt, a PowerShell
		data file parsed with the same Import-PowerShellDataFile used for layout and configuration
		.psd1 files. Close-Workspace reads it back through this function and closes exactly those
		windows and tabs.

		The tracker is the ONLY input to a teardown. Ownership is deliberately never re-derived from
		WorkspaceActions: a single-instance app such as Obsidian, already running because an earlier
		workspace opened it, is absent from a later workspace's entry and therefore survives that
		workspace being closed. Re-deriving from configuration would list it under both and lose
		that distinction.

		Each entry describes one Open-Workspace invocation. A plain open replaces the file (it
		resets the virtual desktops, so nothing earlier survives it); every -Alongside open appends,
		so the same workspace name can legitimately appear more than once - those are separate
		instances with separate windows.

		Reading never throws. A missing file returns $null, and so does an unparseable one, so
		callers can treat "no tracker" as a single case. A file that parses but holds no entries
		returns an object with an empty Entries array instead: "the tracker exists and nothing is
		open" is a different answer from "there is no tracker", and Close-Workspace reports them
		differently.

	.PARAMETER Workspace
		Optional. Return only the entries for these workspace names (case-insensitive). Entries
		keep their recorded order, so the oldest open for a name comes first.

	.PARAMETER StatePath
		Full path to the state file. Defaults to Workflow\State\OpenWorkspaces.txt inside the
		repository this function was loaded from.

	.OUTPUTS
		[pscustomobject] with Path and Entries, or $null when there is no readable tracker.

	.EXAMPLE
		$state = Get-WorkspaceState
		if (-not $state) { "nothing has been opened since the tracker was last cleared" }

	.EXAMPLE
		$serverEntries = (Get-WorkspaceState -Workspace 'Server').Entries
		# Every tracked instance of the Server workspace, oldest first.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Position = 0)]
		[string[]]$Workspace,

		[Parameter()]
		[string]$StatePath
	)

	if ([string]::IsNullOrWhiteSpace($StatePath)) {
		$StatePath = Get-WorkspaceStatePath
	}

	if (-not (Test-Path -LiteralPath $StatePath)) {
		return $null
	}

	# Restricted-language parse (data only, no code execution). Any failure is reported as
	# "no tracker" rather than thrown: a corrupt file must not break a workspace open.
	try {
		$data = Import-PowerShellDataFile -LiteralPath $StatePath -ErrorAction Stop
	}
	catch {
		Write-LogDebug " [Get-WorkspaceState] Could not parse the workspace state file => $($_.Exception.Message)" -Style Warning
		return $null
	}

	if (-not $data) {
		return $null
	}

	$entries = @($data.Entries | Where-Object { $_ })

	if ($Workspace) {
		$wanted = @($Workspace | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
		$entries = @($entries | Where-Object { $entryName = [string]$_.Workspace; $wanted | Where-Object { $_ -ieq $entryName } })
	}

	return [pscustomobject]@{
		Path    = $StatePath
		Entries = $entries
	}
}
