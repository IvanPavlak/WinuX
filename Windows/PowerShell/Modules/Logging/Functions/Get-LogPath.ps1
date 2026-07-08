function Get-LogPath {
	<#
	.SYNOPSIS
		Returns the path of the current structured log file, the error log, or the Logs directory.

	.DESCRIPTION
		Resolves logging state if needed and returns one of the active log paths. With no switch it
		returns the current session log file. Useful for opening or tailing logs after a run.

	.PARAMETER ErrorLog
		Return the shared error log path instead of the session log.

	.PARAMETER Directory
		Return the Logs directory path instead of a file.

	.EXAMPLE
		Get-Content (Get-LogPath) -Tail 40
		Show the tail of the current session log.

	.EXAMPLE
		Get-LogPath -ErrorLog
		Return the path of the verbose error log.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$ErrorLog,

		[Parameter(Mandatory = $false)]
		[switch]$Directory
	)
	if (-not $global:LoggingState) {
		Initialize-LoggingState | Out-Null
	}
	if ($Directory) { return $global:LoggingState.LogsDir }
	if ($ErrorLog) { return $global:LoggingState.ErrorFile }
	return $global:LoggingState.SessionFile
}
