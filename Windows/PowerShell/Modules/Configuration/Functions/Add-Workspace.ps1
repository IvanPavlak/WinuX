function Add-Workspace {
	<#
	.SYNOPSIS
		Adds a workspace to Configuration.psd1.
	.DESCRIPTION
		Adds a workspace name to the Workspaces array and creates its
		WorkspaceActions entry in Configuration.psd1.
	.PARAMETER Name
		The workspace name.
	.PARAMETER Actions
		Array of action hashtables for WorkspaceActions.
		Each: @{ Action = "FunctionName"; Parameters = @{ Key = "Value" } }
		If omitted, creates a default Set-WorkspaceWindowLayout action.
	.PARAMETER ConfigurationFilePath
		Override the Configuration.psd1 path (for testing).
	.PARAMETER BackupRoot
		Override the backup sink root. Defaults to Backups\Windows in the repository the
		configuration file belongs to.
	.EXAMPLE
		Add-Workspace -Name "MyWorkspace" -Actions @(
			@{ Action = "Open-Project"; Parameters = @{ Project = "MyProject" } }
			@{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI", "GitHub") } }
			@{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "MyWorkspace" } }
		)
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]$Name,

		[hashtable[]]$Actions,

		[string]$ConfigurationFilePath,

		[string]$BackupRoot
	)

	$configPath = if ($ConfigurationFilePath) { $ConfigurationFilePath } else { $script:ConfigurationPath }
	if (-not $configPath -or -not (Test-Path $configPath)) {
		Write-LogError "Error: Configuration file not found at '$configPath'!"
		return
	}

	$lines = @(Get-Content -Path $configPath)
	$t = "`t"

	# 1. Add to Workspaces array
	$wsSection = Find-ConfigurationSection -Lines $lines -SectionName "Workspaces"
	if (-not $wsSection) {
		Write-LogError "Error: Workspaces section not found!"
		return
	}

	$newLines = [System.Collections.ArrayList]::new($lines)
	$newLines.Insert($wsSection.EndIndex, "$($wsSection.Indent)$t`"$Name`"")
	$lines = @($newLines)

	Write-LogDebug " [Add-Workspace] Added '$Name' to Workspaces array"

	# 2. Add WorkspaceActions entry
	$waSection = Find-ConfigurationSection -Lines $lines -SectionName "WorkspaceActions"
	if (-not $waSection) {
		Write-LogError "Error: WorkspaceActions section not found!"
		return
	}

	if (-not $Actions) {
		$Actions = @(
			@{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = $Name } }
		)
	}

	$base = $waSection.Indent + $t
	$padded = $Name.PadRight(24)
	$actionLines = @("")
	$actionLines += "$base$padded= @("

	foreach ($action in $Actions) {
		$actionLines += ConvertTo-ActionString -Action $action -Indent "$base$t"
	}

	$actionLines += "$base)"

	$newLines = [System.Collections.ArrayList]::new($lines)
	$insertIndex = $waSection.EndIndex
	for ($i = 0; $i -lt $actionLines.Count; $i++) {
		$newLines.Insert($insertIndex + $i, $actionLines[$i])
	}

	# Configuration.psd1 is a tracked file - keep a timestamped undo in the unified backup sink
	# of the repository the file belongs to (so a sandboxed config never pollutes the real sink)
	# before rewriting it. A backup that cannot be taken aborts the write.
	try {
		if (-not $BackupRoot) {
			$BackupRoot = Join-Path -Path (Get-RepositoryPath -StartPath (Split-Path -Path $configPath -Parent)).Repo -ChildPath "Backups\Windows"
		}
		Backup-RepositoryItem -Path $configPath -Category "Config" -Key "Configuration" -BackupRoot $BackupRoot | Out-Null
	}
	catch {
		Write-LogError "Could not back up '$configPath'; aborting without changes. $($_.Exception.Message)"
		return
	}

	Set-Content -Path $configPath -Value $newLines
	Write-LogSuccess "Workspace '$Name' added to Configuration.psd1"
}
