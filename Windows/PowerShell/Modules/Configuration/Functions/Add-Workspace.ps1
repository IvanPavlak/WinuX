function Add-Workspace {
	<#
	.SYNOPSIS
		Adds a workspace to Configuration.local.psd1.
	.DESCRIPTION
		Appends a workspace to the WorkspaceActions list in Configuration.local.psd1 (the base
		Configuration.psd1 with -Base). When the local file has no WorkspaceActions yet, the base
		list is copied in first, because the local array replaces the base one at load. That list
		is the only definition of a workspace: it is both what Open-Workspace offers and
		the order it offers them in, so one entry is written, never two. The entry is either
		an action list (-Actions) or a one-line templated entry (-Template) that stamps out a
		WorkspaceTemplates entry under the new name.
	.PARAMETER Name
		The workspace name.
	.PARAMETER Actions
		Array of action hashtables for WorkspaceActions.
		Each: @{ Action = "FunctionName"; Parameters = @{ Key = "Value" } }
		If omitted, creates a default Set-WorkspaceWindowLayout action.
	.PARAMETER Template
		The name of a WorkspaceTemplates entry. Writes the one-line templated entry
		@{ <Name> = @{ Template = "<Template>" } } instead of an action list; add Variables,
		Overrides or Add to it by hand. Cannot be combined with -Actions.
	.PARAMETER Base
		Write into the base Configuration.psd1 instead of Configuration.local.psd1 (engine work).
	.PARAMETER ConfigurationFilePath
		Override the configuration file path (for testing). Written as it is, with no section
		copied in.
	.PARAMETER BackupRoot
		Override the backup sink root. Defaults to Backups\Windows in the repository the
		configuration file belongs to.
	.EXAMPLE
		Add-Workspace -Name "MyWorkspace" -Actions @(
			@{ Action = "Open-Project"; Parameters = @{ Project = "MyProject" } }
			@{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI", "GitHub") } }
			@{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "MyWorkspace" } }
		)
	.EXAMPLE
		Add-Workspace -Name "MyProject" -Template "Project"
		# Writes @{ MyProject = @{ Template = "Project" } } - the workspace stamps out the Project template
	#>
	[CmdletBinding(DefaultParameterSetName = 'Actions')]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]$Name,

		[Parameter(ParameterSetName = 'Actions')]
		[hashtable[]]$Actions,

		[Parameter(Mandatory, ParameterSetName = 'Template')]
		[string]$Template,

		[switch]$Base,

		[string]$ConfigurationFilePath,

		[string]$BackupRoot
	)

	# Configuration.local.psd1 unless -Base or -ConfigurationFilePath says otherwise; a section
	# the local file lacks is copied in from the base first (see Get-ConfigurationWriteTarget).
	$target = Get-ConfigurationWriteTarget -ConfigurationFilePath $ConfigurationFilePath -Base:$Base -CopySection 'WorkspaceActions'
	if (-not $target) { return }
	$configPath = $target.Path
	$lines = @($target.Lines)
	$t = "`t"

	$waSection = Find-ConfigurationSection -Lines $lines -SectionName "WorkspaceActions"
	if (-not $waSection) {
		Write-LogError "Error: WorkspaceActions section not found!"
		return
	}

	# One ordered entry: a single-key hashtable whose key is the workspace name, appended
	# at the end of the list so the new workspace shows up last in the menu.
	$base = $waSection.Indent + $t
	$padded = $Name.PadRight(24)
	$actionLines = @("")

	if ($PSCmdlet.ParameterSetName -eq 'Template') {
		# A templated entry is one line. The template must exist in the loaded configuration,
		# otherwise the new workspace would only ever report an unknown template.
		$knownTemplates = Get-ConfigSetting -Path 'WorkspaceTemplates'
		if ($knownTemplates -is [System.Collections.IDictionary] -and -not @($knownTemplates.Keys | Where-Object { [string]$_ -ieq $Template })) {
			Write-LogError "Error: WorkspaceTemplates has no template '$Template' (defined: $(@($knownTemplates.Keys | Sort-Object) -join ', '))!"
			return
		}
		$actionLines += "$base@{ $padded= @{ Template = `"$($Template -replace '"', '`"')`" } }"
	}
	else {
		if (-not $Actions) {
			$Actions = @(
				@{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = $Name } }
			)
		}

		$actionLines += "$base@{ $padded= @("

		foreach ($action in $Actions) {
			$actionLines += ConvertTo-ActionString -Action $action -Indent "$base$t$t"
		}

		$actionLines += "$base$t)"
		$actionLines += "$base}"
	}

	$newLines = [System.Collections.ArrayList]::new($lines)
	$insertIndex = $waSection.EndIndex
	for ($i = 0; $i -lt $actionLines.Count; $i++) {
		$newLines.Insert($insertIndex + $i, $actionLines[$i])
	}

	# A timestamped undo goes to the unified backup sink of the repository the file belongs to
	# first; a backup that cannot be taken aborts the write.
	if (-not (Save-ConfigurationFile -Path $configPath -Lines $newLines -BackupRoot $BackupRoot)) { return }
	Write-LogSuccess "Workspace '$Name' added to $($target.FileName)"
}
