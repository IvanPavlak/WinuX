function Get-ObsidianExecutablePath {
	<#
	.SYNOPSIS
		Resolves Obsidian.exe: beside the CLI, in the default install folder, or from the obsidian:// handler.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$candidates = @()
	$cli = Get-ObsidianCliPath
	if ($cli) { $candidates += Join-Path (Split-Path -Parent $cli) 'Obsidian.exe' }
	$candidates += Join-Path $env:LOCALAPPDATA 'Programs\obsidian\Obsidian.exe'

	$handler = (Get-ItemProperty -Path 'HKCU:\Software\Classes\obsidian\shell\open\command' -ErrorAction SilentlyContinue).'(default)'
	if ($handler -match '^"([^"]+\.exe)"') { $candidates += $Matches[1] }

	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate) { return $candidate }
	}
	return $null
}
