function Add-Project {
	<#
	.SYNOPSIS
		Adds a project to Configuration.psd1.
	.DESCRIPTION
		Adds a project name to the Projects array, creates its ProjectActions entry,
		and optionally adds TerminalTabs, ProjectTerminals, and RunnableProjects entries.
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
		If set, adds the project to RunnableProjects.
	.PARAMETER ConfigurationFilePath
		Override the Configuration.psd1 path (for testing).
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

		[string]$ConfigurationFilePath
	)

	$configPath = if ($ConfigurationFilePath) { $ConfigurationFilePath } else { $script:ConfigurationPath }
	if (-not $configPath -or -not (Test-Path $configPath)) {
		Write-LogError "Error: Configuration file not found at '$configPath'!"
		return
	}

	$lines = @(Get-Content -Path $configPath)
	$t = "`t"

	# 1. Add to Projects array
	$projSection = Find-ConfigurationSection -Lines $lines -SectionName "Projects"
	if (-not $projSection) {
		Write-LogError "Error: Projects section not found!"
		return
	}

	$newLines = [System.Collections.ArrayList]::new($lines)
	$newLines.Insert($projSection.EndIndex, "$($projSection.Indent)$t`"$Name`"")
	$lines = @($newLines)

	Write-LogDebug " [Add-Project] Added '$Name' to Projects array"

	# 2. Add ProjectActions entry
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
	$actionLines += "$base$padded= @("

	foreach ($action in $Actions) {
		$actionLines += ConvertTo-ActionString -Action $action -Indent "$base$t"
	}

	$actionLines += "$base)"

	$newLines = [System.Collections.ArrayList]::new($lines)
	$insertIndex = $paSection.EndIndex
	for ($i = 0; $i -lt $actionLines.Count; $i++) {
		$newLines.Insert($insertIndex + $i, $actionLines[$i])
	}
	$lines = @($newLines)

	# 3. Optional: Add TerminalTabs
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

	# 4. Optional: Add to RunnableProjects
	if ($Runnable) {
		$rpSection = Find-ConfigurationSection -Lines $lines -SectionName "RunnableProjects"
		if ($rpSection) {
			$newLines = [System.Collections.ArrayList]::new($lines)
			$newLines.Insert($rpSection.EndIndex, "$($rpSection.Indent)$t`"$Name`"")
			$lines = @($newLines)
		}
	}

	# 5. Optional: Add to ProjectTerminals
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

	Set-Content -Path $configPath -Value $lines
	Write-LogSuccess "Project '$Name' added to Configuration.psd1"
}
