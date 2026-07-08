function Open-VSCodeWorkspace {
	<#
	.SYNOPSIS
		Opens a VS Code multi-root workspace (*.code-workspace) from the Workspaces folder.

	.DESCRIPTION
		Opens one or more *.code-workspace files stored in the repository's
		VSCode\Workspaces folder (Projects.Self.VSCodeWorkspaces). A workspace is addressed
		by its file base name (e.g. "Consolidation" => Consolidation.code-workspace).

		When -VSCodeWorkspace is omitted, shows an interactive selection menu of all
		available workspaces via Resolve-Selection. A workspace already open (detected by
		its "<name> (Workspace)" window title) is skipped.

		This is the workspace counterpart to Open-VSCode: where Open-VSCode opens a project
		FOLDER, Open-VSCodeWorkspace opens a .code-workspace FILE. Open-Workspace reroutes
		its Open-VSCode action here when a -VSCodeWorkspace override is active, so the
		workspace opens in place of the project folder and the layout logic can target it.

	.PARAMETER VSCodeWorkspace
		One or more workspace names (file base names) as found in the Workspaces folder.
		Omit to show the interactive selection menu.

	.EXAMPLE
		Open-VSCodeWorkspace
		# Shows the workspace selection menu.

	.EXAMPLE
		Open-VSCodeWorkspace -VSCodeWorkspace Consolidation
		# Opens Consolidation.code-workspace in VS Code.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Position = 0)]
		[string[]]$VSCodeWorkspace
	)

	$workspacesDir = $global:MachineSpecificPaths.Projects.Self.VSCodeWorkspaces

	if ([string]::IsNullOrWhiteSpace($workspacesDir) -or -not (Test-Path $workspacesDir)) {
		Write-LogError "VS Code workspaces folder not found => [$workspacesDir]"
		return
	}

	$available = Get-VSCodeWorkspaceNames

	if (-not $available -or $available.Count -eq 0) {
		Write-LogWarning "No VS Code workspaces found in [$workspacesDir]"
		return
	}

	$resolveParams = @{
		InputObject              = $VSCodeWorkspace
		OptionList               = $available
		MenuTitle                = "[Available VS Code workspaces]"
		AllowEmptyPromptResponse = $true
		AllowMultipleSelections  = $true
	}

	$selected = Resolve-Selection @resolveParams

	if (-not $selected) {
		Write-LogWarning "No VS Code workspace selected!"
		return
	}

	$opened = @()

	foreach ($name in $selected) {
		$workspaceFile = Join-Path $workspacesDir "$name.code-workspace"

		if (-not (Test-Path $workspaceFile)) {
			Write-LogError "VS Code workspace file not found => [$workspaceFile]"
			continue
		}

		Write-LogStep "Opening VS Code workspace [$name]..."

		$alreadyOpen = Test-ProjectAlreadyOpen -ProjectName "$name (Workspace)" -ProcessName "Code" -ApplicationName "VSCode"

		if (-not $alreadyOpen) {
			try {
				Start-Process -FilePath "code" -ArgumentList "-n", "`"$workspaceFile`"" -NoNewWindow -ErrorAction Stop
				Write-LogSuccess "Opened VS Code workspace [$name]!"
			}
			catch {
				Write-LogError "Error opening VS Code workspace [$name] => $($_.Exception.Message)"
				continue
			}
		}

		$opened += $name
	}

	return $opened
}
