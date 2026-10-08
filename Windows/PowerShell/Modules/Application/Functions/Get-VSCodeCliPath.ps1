function Get-VSCodeCliPath {
	<#
	.SYNOPSIS
		Returns the path of the VS Code command line (code.cmd), or $null when VS Code is not installed.

	.DESCRIPTION
		Prefers `code` on PATH. A session that installed VS Code a moment ago (Bootstrap's WinGet
		step) does not see the PATH entry the installer added, so when `code` is not found the
		installer's two locations are checked: the per-user install
		(%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd) and the machine-wide install
		(%ProgramFiles%\Microsoft VS Code\bin\code.cmd). The first that exists wins.

	.EXAMPLE
		$code = Get-VSCodeCliPath
		if ($code) { & $code --list-extensions }
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param()

	$command = Get-Command -Name "code" -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($command) {
		return [string]$command.Source
	}

	$candidates = @(
		(Join-Path ([string]$env:LOCALAPPDATA) "Programs\Microsoft VS Code\bin\code.cmd"),
		(Join-Path ([string]$env:ProgramFiles) "Microsoft VS Code\bin\code.cmd")
	)
	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate) {
			return $candidate
		}
	}

	return $null
}
