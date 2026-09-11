function Get-ObsidianCliPath {
	<#
	.SYNOPSIS
		Resolves the Obsidian CLI: `obsidian` on PATH, else Obsidian.com beside the installed exe.
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
