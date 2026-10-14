function Get-ObsidianWorkspaceNames {
	<#
	.SYNOPSIS
		Reads the saved workspace names from the vault's .obsidian\workspaces.json.

	.DESCRIPTION
		Returns the names of the workspaces the core Workspaces plugin saved in
		<VaultDirectory>\.obsidian\workspaces.json (the keys of its "workspaces" object). Returns
		an empty array when -VaultDirectory is empty, when the file does not exist or holds no
		workspaces, and when it does not parse. Reading the file rather than asking the CLI works
		before Obsidian is running; Open-Obsidian uses it for the same-named match, the menu and
		the warning an unknown -Workspace name gets.

	.PARAMETER VaultDirectory
		The vault root - the folder that holds the .obsidian folder, normally
		$MachineSpecificPaths.ObsidianDirectory.

	.OUTPUTS
		[string[]] The saved workspace names, possibly empty.

	.EXAMPLE
		Get-ObsidianWorkspaceNames -VaultDirectory $MachineSpecificPaths.ObsidianDirectory
		Returns the names Open-Obsidian can load, e.g. Server, Empty.
	#>
	[CmdletBinding()]
	[OutputType([object[]])]
	param (
		[Parameter()]
		[string]$VaultDirectory
	)

	if ([string]::IsNullOrWhiteSpace($VaultDirectory)) { return @() }

	$workspacesFile = Join-Path $VaultDirectory '.obsidian\workspaces.json'
	if (-not (Test-Path -LiteralPath $workspacesFile)) {
		Write-LogDebug " [Open-Obsidian] No workspaces.json at [$workspacesFile]" -Style Warning
		return @()
	}

	try {
		$json = Get-Content -LiteralPath $workspacesFile -Raw | ConvertFrom-Json
		if ($json.workspaces) {
			return @($json.workspaces.PSObject.Properties | ForEach-Object { $_.Name })
		}
	}
	catch {
		Write-LogDebug " [Open-Obsidian] Could not parse [$workspacesFile] => $($_.Exception.Message)" -Style Warning
	}
	return @()
}
