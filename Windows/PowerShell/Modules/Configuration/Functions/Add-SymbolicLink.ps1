function Add-SymbolicLink {
	<#
	.SYNOPSIS
		Adds a symbolic link entry to Configuration.local.psd1.
	.DESCRIPTION
		Creates a new PathTemplates.SymbolicLinks entry with Path and Target in
		Configuration.local.psd1 (the base Configuration.psd1 with -Base). SymbolicLinks is a
		hashtable and deep-merges, so a local file without one only gains an empty block for the
		new entry; the base links stay.
		Supports both simple (single link) and nested (multiple files) entries.
	.PARAMETER Name
		Name for the symbolic link entry (typically the app name).
	.PARAMETER Path
		The symlink path (where the link should be created). Use placeholders.
	.PARAMETER Target
		The actual file path (target of the link). Use placeholders.
	.PARAMETER Links
		For nested entries: array of hashtables with Name, Path, and Target keys.
	.PARAMETER Base
		Write into the base Configuration.psd1 instead of Configuration.local.psd1 (engine work).
	.PARAMETER ConfigurationFilePath
		Override the configuration file path (for testing). Written as it is, with no section
		copied in.
	.PARAMETER BackupRoot
		Override the backup sink root. Defaults to Backups\Windows in the repository the
		configuration file belongs to.
	.EXAMPLE
		Add-SymbolicLink -Name "MyApp" -Path "{AppData}\MyApp\config.json" -Target "{RepoRoot}\MyApp\config.json"
	.EXAMPLE
		Add-SymbolicLink -Name "MyApp" -Links @(
			@{ Name = "Settings"; Path = "{AppData}\MyApp\settings.json"; Target = "{RepoRoot}\MyApp\settings.json" }
			@{ Name = "Config"; Path = "{AppData}\MyApp\config.yaml"; Target = "{RepoRoot}\MyApp\config.yaml" }
		)
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]$Name,

		[Parameter(Mandatory, ParameterSetName = "Simple")]
		[string]$Path,

		[Parameter(Mandatory, ParameterSetName = "Simple")]
		[string]$Target,

		[Parameter(Mandatory, ParameterSetName = "Nested")]
		[hashtable[]]$Links,

		[switch]$Base,

		[string]$ConfigurationFilePath,

		[string]$BackupRoot
	)

	# Configuration.local.psd1 unless -Base or -ConfigurationFilePath says otherwise; a section
	# the local file lacks is copied in from the base first (see Get-ConfigurationWriteTarget).
	$target = Get-ConfigurationWriteTarget -ConfigurationFilePath $ConfigurationFilePath -Base:$Base -HashtableSection 'PathTemplates.SymbolicLinks'
	if (-not $target) { return }
	$configPath = $target.Path
	$lines = @($target.Lines)
	$section = Find-ConfigurationSection -Lines $lines -SectionName "SymbolicLinks"
	if (-not $section) {
		Write-LogError "Error: SymbolicLinks section not found in $($target.FileName)!"
		return
	}

	$t = "`t"
	$base = $section.Indent + $t
	$padded = $Name.PadRight(21)
	$entryLines = @()

	if ($PSCmdlet.ParameterSetName -eq "Simple") {
		$entryLines += "$base$padded= @{"
		$entryLines += "$base${t}Path   = `"$Path`""
		$entryLines += "$base${t}Target = `"$Target`""
		$entryLines += "$base}"
	}
	else {
		$entryLines += "$base$padded= @{"
		foreach ($link in $Links) {
			$linkPadded = $link.Name.PadRight(14)
			$entryLines += "$base$t$linkPadded= @{"
			$entryLines += "$base$t${t}Path   = `"$($link.Path)`""
			$entryLines += "$base$t${t}Target = `"$($link.Target)`""
			$entryLines += "$base$t}"
		}
		$entryLines += "$base}"
	}

	$newLines = [System.Collections.ArrayList]::new($lines)
	$insertIndex = $section.EndIndex
	for ($i = 0; $i -lt $entryLines.Count; $i++) {
		$newLines.Insert($insertIndex + $i, $entryLines[$i])
	}

	# A timestamped undo goes to the unified backup sink of the repository the file belongs to
	# first; a backup that cannot be taken aborts the write.
	if (-not (Save-ConfigurationFile -Path $configPath -Lines $newLines -BackupRoot $BackupRoot)) { return }
	Write-LogSuccess "Symbolic link '$Name' added to $($target.FileName)"

	if (Test-LogVerbose) {
		Write-LogDebug "[Add-SymbolicLink] Inserted at line $insertIndex"
		$entryLines | ForEach-Object { Write-LogDebug "  $_" }
	}
}
