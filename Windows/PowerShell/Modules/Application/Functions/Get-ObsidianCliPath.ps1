function Get-ObsidianCliPath {
	<#
	.SYNOPSIS
		Resolves the Obsidian CLI: `obsidian` on PATH, else Obsidian.com beside the installed exe.

	.DESCRIPTION
		Returns the path of the first `obsidian` application on PATH (what registering the CLI under
		Settings > General > Advanced > Command line interface adds), else
		%LOCALAPPDATA%\Programs\obsidian\Obsidian.com when it exists, else $null. Obsidian.com is
		present whether or not the CLI toggle is on, so a path does not mean the CLI will answer;
		Open-Obsidian checks the answer itself. A $null result makes Open-Obsidian fall back to a
		plain launch.

	.OUTPUTS
		[string] The CLI path, or $null.

	.EXAMPLE
		Get-ObsidianCliPath
		Returns e.g. C:\Users\You\AppData\Local\Programs\obsidian\Obsidian.com.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$onPath = Get-Command -Name 'obsidian' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($onPath) { return $onPath.Source }

	$installed = Join-Path $env:LOCALAPPDATA 'Programs\obsidian\Obsidian.com'
	if (Test-Path -LiteralPath $installed) { return $installed }

	return $null
}
