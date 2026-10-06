function Invoke-StartupRepositoryUpdate {
	<#
	.SYNOPSIS
		Updates the configured repositories once per interval, from the profile's idle-time hook.

	.DESCRIPTION
		The automatic repository update. The profile queues it as the startup stage
		"RepositoryUpdate", so it runs after the first prompt is drawn and the shell has been
		idle for a moment - shell start itself pays nothing.

		Off unless `RepositoryUpdate.Startup.Enabled` is $true. Throttled by a stamp file
		(`Logs\.last-repository-update`): when the last run is younger than
		`RepositoryUpdate.Startup.IntervalHours` (default 24) the call returns immediately. The
		stamp records when the last run happened, so a machine that was off for days updates on
		its first shell back. It is written before the update starts, so a run that fails is not
		retried until the interval has passed again (-Force reruns it at any time).

		Several shells opened at once - a workspace opening its terminals - run it exactly once:
		the run is claimed with a lock file (`Logs\.repository-update.lock`) created atomically
		and held open for the whole run, and the stamp is checked again once the lock is held. A
		shell that loses the claim returns silently. A lock left by a shell that died mid-run is
		recognised because Windows lets it be deleted (a live holder's open handle prevents
		that) and is cleared by the next shell.

		Which groups: `RepositoryUpdate.Startup.Scope` when it is set, otherwise
		`BootstrapConfig.RepositoryUpdateScope`, otherwise every group - resolved by
		Resolve-RepositoryUpdateScope, so the per-machine-type shape and the fallbacks are
		Bootstrap's.

		How: `Update-Repositories -NoClone -Quiet` - a repository missing on this machine is
		listed as skipped, never cloned, so nothing ever asks for Administrator; one line per
		repository plus a totals line; local changes are stashed and restored as always; the
		default branch follows `RepositoryUpdate.IncludeDefaultBranch`.

		Never throws: an error is logged and the shell carries on.

	.PARAMETER Force
		Run now, ignoring Enabled and the interval. The stamp is still written.

	.PARAMETER RedrawPrompt
		After a run, draw the prompt again below the summary. The profile passes it: the update
		runs from the idle-time hook after the prompt is already on screen, so its output pushes
		the prompt away and PSReadLine keeps waiting with no prompt visible. Redrawing uses
		PSReadLine's InvokePrompt at the current console row, after a carriage return (output
		written during ReadLine leaves the cursor past column 0). Nothing happens when no update
		ran, outside PSReadLine, or if the redraw fails.

	.EXAMPLE
		Invoke-StartupRepositoryUpdate
		Updates the repositories if the startup update is enabled and the interval has passed.

	.EXAMPLE
		Invoke-StartupRepositoryUpdate -Force
		Runs the startup update right now, exactly as a new shell would.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$Force,

		[Parameter(Mandatory = $false)]
		[switch]$RedrawPrompt
	)

	$startup = Get-ConfigSetting -Path 'RepositoryUpdate.Startup'
	$enabled = if ($startup -and $null -ne $startup.Enabled) { [bool]$startup.Enabled } else { $false }
	$intervalHours = if ($startup -and $null -ne $startup.IntervalHours) { [double]$startup.IntervalHours } else { 24 }

	if (-not $enabled -and -not $Force) { return }

	$lock = $null
	$lockFile = $null
	$ran = $false
	try {
		if (-not $global:LoggingState) { Initialize-LoggingState | Out-Null }
		$logsDir = $global:LoggingState.LogsDir
		if (-not (Test-Path -LiteralPath $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }

		$stampFile = Join-Path $logsDir ".last-repository-update"
		$lockFile = Join-Path $logsDir ".repository-update.lock"

		# Cheap early exit for the common case: the stamp is fresh, so there is nothing to claim.
		if (-not $Force -and (Test-RepositoryUpdateStampFresh -StampFile $stampFile -IntervalHours $intervalHours)) { return }

		# Several shells start at once when a workspace opens its terminals, and checking the stamp
		# then writing it is not atomic - measured: two to four of four simultaneous shells ran.
		# Exactly one shell wins the lock instead. The winner holds it open with no sharing for the
		# whole run, so Windows refuses to delete it while that shell lives; a lock that CAN be
		# deleted was left by a shell that died mid-run, and is cleared here.
		if (Test-Path -LiteralPath $lockFile) {
			try { Remove-Item -LiteralPath $lockFile -Force -ErrorAction Stop } catch { return }
		}
		try {
			$lock = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
		}
		catch [System.IO.IOException] {
			return
		}

		# Re-check under the lock: another shell may have finished a run between the early check
		# and the claim. The stamp is still written before the update, so a run that fails midway
		# is not retried until the interval has passed (-Force reruns it).
		if (-not $Force -and (Test-RepositoryUpdateStampFresh -StampFile $stampFile -IntervalHours $intervalHours)) { return }
		Set-Content -LiteralPath $stampFile -Value (Get-Date -Format 'o') -Encoding UTF8 -Force -ErrorAction Stop
		$ran = $true

		$scopePath = if ($null -ne (Get-ConfigSetting -Path 'RepositoryUpdate.Startup.Scope')) {
			'RepositoryUpdate.Startup.Scope'
		}
		else {
			'BootstrapConfig.RepositoryUpdateScope'
		}
		$scope = Resolve-RepositoryUpdateScope -Path $scopePath

		if ($scope.All) {
			Update-Repositories -All -NoClone -Quiet
		}
		else {
			Update-Repositories -Group $scope.Groups -NoClone -Quiet
		}
	}
	catch {
		Write-LogError "Startup repository update failed: $_"
	}
	finally {
		if ($lock) {
			$lock.Dispose()
			Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
		}
	}

	# Only after an update was attempted - the disabled, throttled and lost-the-lock paths print
	# nothing, so there is no prompt to restore.
	if ($ran -and $RedrawPrompt -and ('Microsoft.PowerShell.PSConsoleReadLine' -as [type])) {
		try {
			[Console]::Write("`r")
			[Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt($null, [Console]::CursorTop)
		}
		catch { }
	}
}
