function Stop-Logging {
	<#
	.SYNOPSIS
		Stop transcript logging, show a duration summary, and prune old structured logs.

	.DESCRIPTION
		Ends the PowerShell transcript started by Start-Logging, calculates and displays the total
		duration, and shows the Desktop log file location (behavior preserved from the historical
		bootstrap logging). Finally enforces structured-log retention via Clear-OldLogs so the Logs
		folder stays bounded.

	.EXAMPLE
		Start-Logging
		# ... do work ...
		Stop-Logging
		# Output: Log file location => C:\Users\You\Desktop\BootstrapLog_2026-04-30_14-32-01.log
	#>
	[CmdletBinding()]
	param()

	$endTime = Get-Date
	$duration = $endTime - $global:startTime

	Stop-Transcript | Out-Null
	Write-LogTitle "Logging stopped"

	$hours = [math]::Floor($duration.TotalHours)
	$minutes = $duration.Minutes
	$seconds = $duration.Seconds

	$timeString = ""
	if ($hours -gt 0) { $timeString += "$hours hour$(if($hours -ne 1){'s'}) " }
	if ($minutes -gt 0) { $timeString += "$minutes minute$(if($minutes -ne 1){'s'}) " }
	if ($seconds -gt 0 -or $timeString -eq "") { $timeString += "$seconds second$(if($seconds -ne 1){'s'})" }

	# These two summary lines use mid-sentence "=>" (not the leading "=> " result prefix) and a
	# non-success green, so they are written directly to preserve the exact historical output.
	Write-Host -ForegroundColor Green "`nLog file location => $global:logPath"
	Write-Host -ForegroundColor White "`nTotal duration => $timeString"

	try { Clear-OldLogs } catch { }
}
