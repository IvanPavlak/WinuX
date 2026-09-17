function Add-Project {
	<#
	.SYNOPSIS
		Adds a project to Configuration.psd1.
	.DESCRIPTION
		Appends a project to the ProjectActions list in Configuration.psd1, and optionally
		adds TerminalTabs, ProjectTerminals and RunnableProjectMappings entries. Each list
		is the only definition of its side of a project - what Open-Project offers and the
		order it offers it in comes from ProjectActions alone, so one entry is written per
		list, never a name in one place and a definition in another.
	.PARAMETER Name
		The project name.
	.PARAMETER Actions
		Array of action hashtables for ProjectActions.
		If omitted, creates default Open-VSCode + Open-ProjectTerminals-Or-RunProject actions.
	.PARAMETER TerminalTabs
		Optional array of terminal tab hashtables: @{ Title = "..."; Path = "..." }
	.PARAMETER BasePath
		Optional dot-notation base path for ProjectTerminals entry (e.g., "Projects.MyProject").
	.PARAMETER Paths
		Optional array of path names for ProjectTerminals entry (e.g., @("ROOT", "API")).
	.PARAMETER Runnable
		If set, adds a RunnableProjectMappings entry so Run-Project offers the project.
		The commands stay empty: every configured path gets a terminal tab, and you fill
		in `Commands = @{ <PathKey> = "<command>" }` for the paths that run something.
	.PARAMETER ConfigurationFilePath
		Override the Configuration.psd1 path (for testing).
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

	Set-Content -Path $configPath -Value $lines
	Write-LogSuccess "Project '$Name' added to Configuration.psd1"
}
