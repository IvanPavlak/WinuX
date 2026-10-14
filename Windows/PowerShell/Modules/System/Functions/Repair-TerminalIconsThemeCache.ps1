function Repair-TerminalIconsThemeCache {
	<#
	.SYNOPSIS
		Moves aside every Terminal-Icons theme cache file that no longer parses, so the module can
		import again.

	.DESCRIPTION
		Terminal-Icons keeps its themes and preferences as Clixml files under
		%APPDATA%\powershell\Community\Terminal-Icons and rewrites every one of them on each
		import. Two shells importing the module in the same instant - a workspace opening several
		tabs at once - race on those writes, and a file can end up torn: two writes spliced
		mid-line. From then on every Import-Module Terminal-Icons fails on that file
		("Import-Clixml: Name attribute for dictionary key is incorrectly specified") and no
		directory listing carries icons until the file is gone.

		Every .xml file in the cache folder is read with Import-Clixml. One that fails to parse is
		renamed to <name>.corrupt-<yyyyMMdd-HHmmss> beside the original, with a warning naming it;
		the module regenerates the file from its built-in themes on the next import, and the
		quarantined copy stays for inspection. Nothing is deleted, files that parse are left
		alone, and a file that cannot be renamed is reported as an error and left where it is. A
		cache folder that does not exist means there is nothing to repair.

	.PARAMETER Path
		The Terminal-Icons theme cache folder. Defaults to
		%APPDATA%\powershell\Community\Terminal-Icons, where the module keeps it on Windows.

	.OUTPUTS
		[System.IO.FileInfo[]] - the quarantined files, under their new names; nothing when every
		file parsed or the folder does not exist.

	.EXAMPLE
		Repair-TerminalIconsThemeCache
		Moves a torn theme file aside; the next Import-Module Terminal-Icons succeeds.

	.EXAMPLE
		Repair-TerminalIconsThemeCache -Path "D:\Backup\Terminal-Icons"
		Probes a copy of the cache somewhere else.
	#>
	[CmdletBinding()]
	[OutputType([System.IO.FileInfo[]])]
	param(
		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$Path = (Join-Path $env:APPDATA "powershell\Community\Terminal-Icons")
	)

	$quarantined = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

	if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
		Write-LogDebug "No Terminal-Icons theme cache at [$Path] - nothing to repair"
		return [System.IO.FileInfo[]]$quarantined.ToArray()
	}

	$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
	foreach ($file in @(Get-ChildItem -LiteralPath $Path -Filter "*.xml" -File)) {
		try {
			$null = Import-Clixml -LiteralPath $file.FullName -ErrorAction Stop
			Write-LogDebug "Theme cache file [$($file.Name)] parses"
			continue
		}
		catch {
			$reason = $_.Exception.Message
		}

		$newName = "$($file.Name).corrupt-$stamp"
		try {
			Rename-Item -LiteralPath $file.FullName -NewName $newName -ErrorAction Stop
			$moved = Get-Item -LiteralPath (Join-Path $Path $newName)
			$quarantined.Add($moved)
			Write-LogWarning "Terminal-Icons theme cache file [$($file.Name)] does not parse ($reason) - moved to [$($moved.FullName)]; the module regenerates it on the next import"
		}
		catch {
			Write-LogError "Terminal-Icons theme cache file [$($file.FullName)] does not parse ($reason) and could not be moved aside => $($_.Exception.Message)" -Exception $_
		}
	}

	return [System.IO.FileInfo[]]$quarantined.ToArray()
}
