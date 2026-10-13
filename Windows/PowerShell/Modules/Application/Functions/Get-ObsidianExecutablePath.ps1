function Get-ObsidianExecutablePath {
	<#
	.SYNOPSIS
		Resolves Obsidian.exe: beside the CLI, in the default install folder, or from the obsidian:// handler.

	.DESCRIPTION
		Collects the candidates in this order: Obsidian.exe in the folder of the CLI
		(Get-ObsidianCliPath), %LOCALAPPDATA%\Programs\obsidian\Obsidian.exe, and the executable
		of the obsidian:// protocol handler registered under
		HKCU:\Software\Classes\obsidian\shell\open\command. Returns the first candidate that
		exists, $null when none does. Start-ObsidianDetached needs the executable itself, because a
		process created through WMI cannot be started from a URI alone.

	.OUTPUTS
		[string] The path of Obsidian.exe, or $null.

	.EXAMPLE
		Get-ObsidianExecutablePath
		Returns e.g. C:\Users\You\AppData\Local\Programs\obsidian\Obsidian.exe.
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
