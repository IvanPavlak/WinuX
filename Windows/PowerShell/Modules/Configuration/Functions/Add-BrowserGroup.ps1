function Add-BrowserGroup {
	<#
	.SYNOPSIS
		Adds a browser group to Configuration.local.psd1.
	.DESCRIPTION
		Creates a new BrowserGroups entry in Configuration.local.psd1 (the base Configuration.psd1
		with -Base). When the local file has no BrowserGroups yet, the base list is copied in
		first, because the local array replaces the base one at load.
		Supports named URLs (recommended) and simple URL lists.
	.PARAMETER GroupName
		Unique name for the browser group.
	.PARAMETER Urls
		Array of URL hashtables: @{ Name = "Label"; Url = "https://..." }
	.PARAMETER SimpleUrls
		Array of URL strings for simple groups without labels.
	.PARAMETER Base
		Write into the base Configuration.psd1 instead of Configuration.local.psd1 (engine work).
	.PARAMETER ConfigurationFilePath
		Override the configuration file path (for testing). Written as it is, with no section
		copied in.
	.PARAMETER BackupRoot
		Override the backup sink root. Defaults to Backups\Windows in the repository the
		configuration file belongs to.
	.EXAMPLE
		Add-BrowserGroup -GroupName "DevTools" -Urls @(
			@{ Name = "GitHub"; Url = "https://github.com" }
			@{ Name = "StackOverflow"; Url = "https://stackoverflow.com" }
		)
	.EXAMPLE
		Add-BrowserGroup -GroupName "Google" -SimpleUrls @("https://www.google.com/")
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]$GroupName,

		[Parameter(Mandatory, ParameterSetName = "Named")]
		[hashtable[]]$Urls,

		[Parameter(Mandatory, ParameterSetName = "Simple")]
		[string[]]$SimpleUrls,

		[switch]$Base,

		[string]$ConfigurationFilePath,

		[string]$BackupRoot
	)

	# Configuration.local.psd1 unless -Base or -ConfigurationFilePath says otherwise; a section
	# the local file lacks is copied in from the base first (see Get-ConfigurationWriteTarget).
	$target = Get-ConfigurationWriteTarget -ConfigurationFilePath $ConfigurationFilePath -Base:$Base -CopySection 'BrowserGroups'
	if (-not $target) { return }
	$configPath = $target.Path
	$lines = @($target.Lines)
	$section = Find-ConfigurationSection -Lines $lines -SectionName "BrowserGroups"
	if (-not $section) {
		Write-LogError "Error: BrowserGroups section not found in $($target.FileName)!"
		return
	}

	$t = "`t"
	$base = $section.Indent + $t
	$entryLines = @()

	if ($PSCmdlet.ParameterSetName -eq "Simple") {
		$entryLines += "$base@{ $GroupName = @("
		foreach ($url in $SimpleUrls) {
			$entryLines += "$base$t$t`"$url`""
		}
		$entryLines += "$base$t)"
		$entryLines += "$base}"
	}
	else {
		$entryLines += "$base@{ $GroupName = @("
		foreach ($url in $Urls) {
			$entryLines += "$base$t$t@{ Name = `"$($url.Name)`"; Url = `"$($url.Url)`" }"
		}
		$entryLines += "$base$t)"
		$entryLines += "$base}"
	}

	$newLines = [System.Collections.ArrayList]::new($lines)
	$insertIndex = $section.EndIndex
	$newLines.Insert($insertIndex, "")
	for ($i = 0; $i -lt $entryLines.Count; $i++) {
		$newLines.Insert($insertIndex + 1 + $i, $entryLines[$i])
	}

	# A timestamped undo goes to the unified backup sink of the repository the file belongs to
	# first; a backup that cannot be taken aborts the write.
	if (-not (Save-ConfigurationFile -Path $configPath -Lines $newLines -BackupRoot $BackupRoot)) { return }
	Write-LogSuccess "Browser group '$GroupName' added to $($target.FileName)"

	if (Test-LogVerbose) {
		Write-LogDebug "[Add-BrowserGroup] Inserted at line $insertIndex"
		$entryLines | ForEach-Object { Write-LogDebug "  $_" }
	}
}
