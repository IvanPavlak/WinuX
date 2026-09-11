function Get-ObsidianWorkspaceNames {
	<#
	.SYNOPSIS
		Reads the saved workspace names from the vault's .obsidian\workspaces.json.
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
