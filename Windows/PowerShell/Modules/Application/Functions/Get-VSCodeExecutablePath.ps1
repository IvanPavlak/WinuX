function Get-VSCodeExecutablePath {
	<#
	.SYNOPSIS
		Resolves Code.exe for a detached launch, or $null when VS Code is not installed.

	.DESCRIPTION
		Collects the candidates in this order: Code.exe one folder above the command line
		(Get-VSCodeCliPath returns <install>\bin\code.cmd), the per-user install
		(%LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe) and the machine-wide install
		(%ProgramFiles%\Microsoft VS Code\Code.exe). Returns the first candidate that exists,
		$null when none does. Start-VSCodeDetached needs the executable itself: code.cmd runs
		through cmd.exe and the VS Code CLI, and a process created through WMI must be the final
		executable.

	.OUTPUTS
		[string] The path of Code.exe, or $null.

	.EXAMPLE
		Get-VSCodeExecutablePath
		Returns e.g. C:\Users\You\AppData\Local\Programs\Microsoft VS Code\Code.exe.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param ()

	$candidates = @()
	$cli = Get-VSCodeCliPath
	if ($cli) {
		$installRoot = Split-Path -Parent (Split-Path -Parent $cli)
		if ($installRoot) {
			$candidates += Join-Path $installRoot 'Code.exe'
		}
	}
	$candidates += Join-Path ([string]$env:LOCALAPPDATA) 'Programs\Microsoft VS Code\Code.exe'
	$candidates += Join-Path ([string]$env:ProgramFiles) 'Microsoft VS Code\Code.exe'

	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate) {
			return $candidate
		}
	}
	return $null
}
