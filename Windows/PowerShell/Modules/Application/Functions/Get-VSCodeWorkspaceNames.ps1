function Get-VSCodeWorkspaceNames {
	<#
	.SYNOPSIS
		Lists the available VS Code workspace names (*.code-workspace files).

	.DESCRIPTION
		Enumerates the workspaces directory (Projects.Self.VSCodeWorkspaces, i.e.
		<repo>\VSCode\Workspaces) and returns each workspace's base name - the file name
		without the .code-workspace extension. Returns an empty array when the folder is
		missing or contains no workspace files.

		Shared by Open-VSCodeWorkspace (interactive selection) and Open-Workspace (the
		-VSCodeWorkspace override menu), so the discovery logic lives in one place.

	.EXAMPLE
		Get-VSCodeWorkspaceNames
		# => @("Consolidation", "Frontend", ...)
	#>
	[CmdletBinding()]
	param()

	$workspacesDir = $global:MachineSpecificPaths.Projects.Self.VSCodeWorkspaces

	if ([string]::IsNullOrWhiteSpace($workspacesDir) -or -not (Test-Path $workspacesDir)) {
		return @()
	}

	return @(
		Get-ChildItem -Path $workspacesDir -Filter "*.code-workspace" -File -ErrorAction SilentlyContinue |
			Select-Object -ExpandProperty BaseName
	)
}
