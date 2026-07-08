function Protect-Log {
	<#
	.SYNOPSIS
		Pins a log file into Logs/Pinned so retention never deletes it.

	.DESCRIPTION
		Copies a log into the Logs/Pinned subfolder, which Clear-OldLogs always skips. Use this to
		keep a log around during ongoing development or while investigating an issue, without
		disabling retention for everything else. The original stays in place (so an active session
		keeps recording to it); the pinned copy is the protected snapshot.

	.PARAMETER Path
		Path of the log file to pin. Defaults to the current session log.

	.PARAMETER ErrorLog
		Pin the shared error log instead of a session log.

	.EXAMPLE
		Protect-Log
		Pin the current session log so it survives pruning.

	.EXAMPLE
		Protect-Log -Path (Get-LogPath)
		Equivalent explicit form.

	.EXAMPLE
		Protect-Log -ErrorLog
		Pin a snapshot of the verbose error log.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false, Position = 0)]
		[string]$Path,

		[Parameter(Mandatory = $false)]
		[switch]$ErrorLog
	)
	if (-not $global:LoggingState) {
		Initialize-LoggingState | Out-Null
	}
	$state = $global:LoggingState

	if (-not $Path) {
		$Path = if ($ErrorLog) { $state.ErrorFile } else { $state.SessionFile }
	}

	if (-not (Test-Path $Path)) {
		Write-LogWarning "No log file to pin at => [$Path]"
		return
	}

	if (-not (Test-Path $state.PinnedDir)) {
		try { New-Item -ItemType Directory -Path $state.PinnedDir -Force | Out-Null }
		catch { Write-LogError "Could not create pinned-logs folder => [$($state.PinnedDir)]" -Exception $_; return }
	}

	$destination = Join-Path $state.PinnedDir (Split-Path $Path -Leaf)
	try {
		Copy-Item -Path $Path -Destination $destination -Force -ErrorAction Stop
		Write-LogSuccess "Pinned log => [$destination]"
	}
	catch {
		Write-LogError "Failed to pin log => $($_.Exception.Message)" -Exception $_
	}
}
