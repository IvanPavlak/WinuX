function Start-Logging {
	<#
	.SYNOPSIS
		Start transcript logging to a Desktop file and open a structured logging session.

	.DESCRIPTION
		Initiates a PowerShell transcript with a timestamped filename on the Desktop (unchanged from
		the historical bootstrap behavior - the Desktop location is preserved for fresh-machine
		parity), setting global $logPath and $startTime for later use by Stop-Logging. Also
		initializes the structured logging session so Write-Log* output is mirrored to the module's
		Logs folder for the duration of the run.

		Used during bootstrap and setup operations for an audit trail. The transcript captures all
		console output to the Desktop file while it displays live; the structured Logs files provide
		the leveled, retention-bounded record.

	.EXAMPLE
		Start-Logging
		Write-LogStep "Operations logged"
		Stop-Logging
	#>
	[CmdletBinding()]
	param()

	$global:logPath = "$env:USERPROFILE\Desktop\BootstrapLog_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
	$global:startTime = Get-Date
	Start-Transcript -Path $global:logPath -Append | Out-Null

	if (-not $global:LoggingState) {
		Initialize-LoggingState | Out-Null
	}

	Write-LogTitle "Logging started"
}
