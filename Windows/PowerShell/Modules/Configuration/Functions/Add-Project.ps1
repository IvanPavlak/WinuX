function Add-Project {
	<#
	.SYNOPSIS
		Adds a project to Configuration.local.psd1.
	.DESCRIPTION
		Appends a project to the ProjectActions list in Configuration.local.psd1 (the base
		Configuration.psd1 with -Base), and optionally
		adds TerminalTabs, ProjectTerminals and RunnableProjectMappings entries. Each list
		is the only definition of its side of a project - what Open-Project offers and the
		order it offers it in comes from ProjectActions alone, so one entry is written per
		list, never a name in one place and a definition in another. Each list the local file
		does not have yet is copied in from the base first, because a local array replaces the
		base one at load; only the lists this call writes are copied.
	.PARAMETER Name
		The project name.
	.PARAMETER Actions
		Array of action hashtables for ProjectActions.
		If omitted, creates default Open-VSCode + Open-ProjectTerminals-Or-RunProject actions.
	.PARAMETER TerminalTabs
		Optional array of terminal tab hashtables: @{ Title = "..."; Path = "..." }, written to a
		TerminalTabs section. The shipped Configuration.psd1 has no TerminalTabs section and no
		function reads one, so this is skipped (nothing is written) unless the file defines it.
	.PARAMETER BasePath
		Optional dot-notation base path for ProjectTerminals entry (e.g., "Projects.MyProject").
	.PARAMETER Paths
		Optional array of path names for ProjectTerminals entry (e.g., @("ROOT", "API")).
	.PARAMETER Runnable
		If set, adds a RunnableProjectMappings entry so Run-Project offers the project.
		The commands stay empty: every configured path gets a terminal tab, and you fill
		in `Commands = @{ <PathKey> = "<command>" }` for the paths that run something.
	.PARAMETER Base
		Write into the base Configuration.psd1 instead of Configuration.local.psd1 (engine work).
	.PARAMETER ConfigurationFilePath
		Override the configuration file path (for testing). Written as it is, with no section
		copied in.
	.PARAMETER BackupRoot
		Override the backup sink root. Defaults to Backups\Windows in the repository the
		configuration file belongs to.
	.EXAMPLE
		Add-Project -Name "NewApp" -TerminalTabs @(
			@{ Title = "Root"; Path = "DEFAULT" }
			@{ Title = "API"; Path = "{ProjectName}\api" }
		) -Runnable
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]$Name,

		[hashtable[]]$Actions,
		[hashtable[]]$TerminalTabs,
		[string]$BasePath,
		[string[]]$Paths,
		[switch]$Runnable,

		[switch]$Base,

		[string]$ConfigurationFilePath,

		[string]$BackupRoot
	)

	# Configuration.local.psd1 unless -Base or -ConfigurationFilePath says otherwise; a list the
	# local file lacks is copied in from the base first (see Get-ConfigurationWriteTarget) - only
	# the lists this call writes, so the local file does not freeze a copy of the others.
	$sectionsToWrite = @('ProjectActions')
	if ($Runnable) { $sectionsToWrite += 'RunnableProjectMappings' }
	if ($BasePath -and $Paths) { $sectionsToWrite += 'ProjectTerminals' }
	$target = Get-ConfigurationWriteTarget -ConfigurationFilePath $ConfigurationFilePath -Base:$Base -CopySection $sectionsToWrite
	if (-not $target) { return }
	$configPath = $target.Path
	$lines = @($target.Lines)
	$t = "`t"

	# 1. Add ProjectActions entry - the project's only definition and its menu position
	$paSection = Find-ConfigurationSection -Lines $lines -SectionName "ProjectActions"
	if (-not $paSection) {
		Write-LogError "Error: ProjectActions section not found!"
		return
	}

	if (-not $Actions) {
		$Actions = @(
			@{ Action = "Open-VSCode"; Parameters = @{ Folder = "{ProjectName}" } }
			@{ Action = "Open-ProjectTerminals-Or-RunProject"; Parameters = @{ Project = "{ProjectName}" } }
		)
	}

	$base = $paSection.Indent + $t
	$padded = $Name.PadRight(28)
	$actionLines = @("")
	$actionLines += "$base@{ $padded= @("

	foreach ($action in $Actions) {
		$actionLines += ConvertTo-ActionString -Action $action -Indent "$base$t$t"
	}

	$actionLines += "$base$t)"
	$actionLines += "$base}"

	$newLines = [System.Collections.ArrayList]::new($lines)
	$insertIndex = $paSection.EndIndex
	for ($i = 0; $i -lt $actionLines.Count; $i++) {
		$newLines.Insert($insertIndex + $i, $actionLines[$i])
	}
	$lines = @($newLines)

	# 2. Optional: Add TerminalTabs
	if ($TerminalTabs) {
		$ttSection = Find-ConfigurationSection -Lines $lines -SectionName "TerminalTabs"
		if ($ttSection) {
			$base = $ttSection.Indent + $t
			$padded = $Name.PadRight(28)
			$tabLines = @("")
			$tabLines += "$base$padded= @("
			foreach ($tab in $TerminalTabs) {
				$tabLines += "$base$t@{ Title = `"$($tab.Title)`"; Path = `"$($tab.Path)`" }"
			}
			$tabLines += "$base)"

			$newLines = [System.Collections.ArrayList]::new($lines)
			$insertIndex = $ttSection.EndIndex
			for ($i = 0; $i -lt $tabLines.Count; $i++) {
				$newLines.Insert($insertIndex + $i, $tabLines[$i])
			}
			$lines = @($newLines)

			Write-LogDebug " [Add-Project] Added TerminalTabs for '$Name'"
		}

	}

	# 3. Optional: Add to RunnableProjectMappings - the Run-Project menu reads this list,
	#    so the mapping is what makes a project runnable; Commands is filled in by hand.
	if ($Runnable) {
		$rpSection = Find-ConfigurationSection -Lines $lines -SectionName "RunnableProjectMappings"
		if ($rpSection) {
			$base = $rpSection.Indent + $t
			$mappingLines = @(
				"$base@{ Name     = `"$Name`";"
				"$base$t`Commands = @{}"
				"$base}"
			)

			$newLines = [System.Collections.ArrayList]::new($lines)
			for ($i = 0; $i -lt $mappingLines.Count; $i++) {
				$newLines.Insert($rpSection.EndIndex + $i, $mappingLines[$i])
			}
			$lines = @($newLines)
		}
	}

	# 4. Optional: Add to ProjectTerminals
	if ($BasePath -and $Paths) {
		$ptSection = Find-ConfigurationSection -Lines $lines -SectionName "ProjectTerminals"
		if ($ptSection) {
			$base = $ptSection.Indent + $t
			$quotedPaths = ($Paths | ForEach-Object { "`"$_`"" }) -join ", "
			$entryLine = "$base@{ Name = `"$Name`"; BasePath = `"$BasePath`"; Paths = @($quotedPaths) }"

			$newLines = [System.Collections.ArrayList]::new($lines)
			$newLines.Insert($ptSection.EndIndex, $entryLine)
			$lines = @($newLines)
		}
	}

	# A timestamped undo goes to the unified backup sink of the repository the file belongs to
	# first; a backup that cannot be taken aborts the write.
	if (-not (Save-ConfigurationFile -Path $configPath -Lines $lines -BackupRoot $BackupRoot)) { return }
	Write-LogSuccess "Project '$Name' added to $($target.FileName)"
}
