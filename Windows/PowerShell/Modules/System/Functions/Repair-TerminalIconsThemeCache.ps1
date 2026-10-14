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

		Every .xml file in the cache folder is read with Import-Clixml. A file that fails is read
		once more after a short pause, because another shell may be in the middle of rewriting it;
		only a file that still fails is renamed to <name>.corrupt-<yyyyMMdd-HHmmss>-<pid> beside
		the original, with a warning naming it. The process id keeps two shells repairing in the
		same second from claiming one rename between them. The module regenerates the file from its
		built-in themes on the next import, and the quarantined copy stays for inspection. Nothing is
		deleted and files that parse are left alone. A file that is gone by the time it is renamed
		was moved aside by another shell repairing the same cache at the same moment - a Debug
		line, not an error - while a file that is still there and cannot be renamed is reported as
		an error and left where it is. A cache folder that does not exist means there is nothing to
		repair.

	.PARAMETER Path
		The Terminal-Icons theme cache folder. Defaults to
		%APPDATA%\powershell\Community\Terminal-Icons, where the module keeps it on Windows.

	.OUTPUTS
		[System.IO.FileInfo[]] - the files this call quarantined, under their new names; nothing
		when every file parsed, the folder does not exist, or another shell moved the file first.

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

	# Long enough for another shell to finish writing one theme file (each is about 60 KB).
	$settleMilliseconds = 250
	$quarantined = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

	if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
		Write-LogDebug "No Terminal-Icons theme cache at [$Path] - nothing to repair"
		return [System.IO.FileInfo[]]$quarantined.ToArray()
	}

	$unreadable = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
	foreach ($file in @(Get-ChildItem -LiteralPath $Path -Filter "*.xml" -File)) {
		if (Test-TerminalIconsCacheFile -Path $file.FullName) {
			Write-LogDebug "Theme cache file [$($file.Name)] parses"
		}
		else {
			$unreadable.Add($file)
		}
	}

	if ($unreadable.Count -eq 0) {
		return [System.IO.FileInfo[]]$quarantined.ToArray()
	}

	Start-Sleep -Milliseconds $settleMilliseconds

	$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
	foreach ($file in $unreadable) {
		if (-not (Test-Path -LiteralPath $file.FullName -PathType Leaf)) {
			Write-LogDebug "Theme cache file [$($file.Name)] was moved aside by another shell"
			continue
		}

		$reason = $null
		if (Test-TerminalIconsCacheFile -Path $file.FullName -Reason ([ref]$reason)) {
			Write-LogDebug "Theme cache file [$($file.Name)] parses on the second read - another shell was writing it"
			continue
		}

		$newName = "$($file.Name).corrupt-$stamp-$PID"
		try {
			Rename-Item -LiteralPath $file.FullName -NewName $newName -ErrorAction Stop
			$moved = Get-Item -LiteralPath (Join-Path $Path $newName) -ErrorAction Stop
			$quarantined.Add($moved)
			Write-LogWarning "Terminal-Icons theme cache file [$($file.Name)] does not parse ($reason) - moved to [$($moved.FullName)]; the module regenerates it on the next import"
		}
		catch {
			if (-not (Test-Path -LiteralPath $file.FullName -PathType Leaf)) {
				Write-LogDebug "Theme cache file [$($file.Name)] was moved aside by another shell"
				continue
			}
			Write-LogError "Terminal-Icons theme cache file [$($file.FullName)] does not parse ($reason) and could not be moved aside => $($_.Exception.Message)" -Exception $_
		}
	}

	return [System.IO.FileInfo[]]$quarantined.ToArray()
}
