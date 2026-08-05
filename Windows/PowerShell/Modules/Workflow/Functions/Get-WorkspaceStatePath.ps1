function Get-WorkspaceStatePath {
	<#
	.SYNOPSIS
		Resolves the path of the open-workspace tracker file.

	.DESCRIPTION
		The single definition of where Save-WorkspaceState writes and Get-WorkspaceState reads, so
		neither has to know the folder depth and the two can never disagree. The file lives at
		Workflow\State\OpenWorkspaces.txt inside the repository this function was loaded from,
		resolved through Get-RepositoryPath rather than by counting parent folders.

		The State folder is git-ignored with a .gitkeep, following Logging\Logs and
		Window\Layouts\CurrentLayout.txt: it is per-machine runtime state describing which windows
		are open right now, which is meaningless on any other machine and in any later session.
		Deleting the file is safe - Close-Workspace then reports that nothing is tracked rather
		than guessing.

		Like Save-CurrentLayout's snapshot the file is named .txt, not .psd1, even though its
		contents are a PowerShell data file: nothing should mistake per-machine runtime state for a
		module manifest or a configuration file that belongs under version control.

	.PARAMETER StartPath
		Directory to anchor the repository search on. Defaults to this function's own location,
		which resolves the repository it was loaded from.

	.OUTPUTS
		[string] full path to OpenWorkspaces.txt. The file itself may not exist yet.

	.EXAMPLE
		Get-Content (Get-WorkspaceStatePath)
		Show the raw tracker contents.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter()]
		[string]$StartPath = $PSScriptRoot
	)

	$modulesRoot = (Get-RepositoryPath -StartPath $StartPath).Modules

	return Join-Path -Path (Join-Path -Path $modulesRoot -ChildPath "Workflow\State") -ChildPath "OpenWorkspaces.txt"
}
