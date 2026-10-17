function Get-VSCodeExecutablePath {
	<#
	.SYNOPSIS
		Resolves Code.exe for a detached launch, or $null when VS Code is not installed.

	.DESCRIPTION
		Returns Code.exe one folder above the command line that Get-VSCodeCliPath resolves
		(<install>\bin\code.cmd), $null when there is no command line or no Code.exe beside it.
		Get-VSCodeCliPath already covers `code` on PATH and both installer locations, so the
		executable is derived from it rather than probed again. Start-VSCodeDetached needs the
		executable itself: code.cmd runs through cmd.exe and the VS Code CLI, and a process
		created through WMI must be the final executable.

	.OUTPUTS
		[string] The path of Code.exe, or $null.

	.EXAMPLE
		Get-VSCodeExecutablePath
		Returns e.g. C:\Users\You\AppData\Local\Programs\Microsoft VS Code\Code.exe.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$cli = Get-VSCodeCliPath
	if (-not $cli) {
		return $null
	}

	$installRoot = Split-Path -Parent (Split-Path -Parent $cli)
	if (-not $installRoot) {
		return $null
	}

	$exe = Join-Path $installRoot 'Code.exe'
	if (Test-Path -LiteralPath $exe) {
		return $exe
	}
	return $null
}
