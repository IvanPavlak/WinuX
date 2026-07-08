function Clear-OldLogs {
	<#
	.SYNOPSIS
		Enforces log retention so the Logs folder stays small but complete.

	.DESCRIPTION
		Prunes session log files (Session_*.log) in the Logs directory by three independent limits,
		applied in order: maximum age in days, maximum number of session files, then maximum total
		size in megabytes (oldest files removed first). The shared error log is trimmed separately by
		its own size cap (the most recent lines are kept).

		Logs in the Logs/Pinned subfolder are NEVER touched - use Protect-Log to move a log there
		when you want to keep it through ongoing development. Called automatically by Stop-Logging;
		safe to run manually at any time. Limits default from $Configuration.Logging.FileLogging.Retention.

	.PARAMETER MaxAgeDays
		Delete session logs older than this many days. Default from config (fallback 7).

	.PARAMETER MaxSessionFiles
		Keep at most this many session logs (newest retained). Default from config (fallback 20).

	.PARAMETER MaxTotalSizeMB
		Cap the combined size of session logs in MB (oldest removed until under cap). Default from config (fallback 50).

	.PARAMETER MaxErrorFileSizeMB
		Trim the error log to its most recent content when it exceeds this many MB. Default from config (fallback 5).

	.EXAMPLE
		Clear-OldLogs
		Prune using the configured retention limits.

	.EXAMPLE
		Clear-OldLogs -MaxSessionFiles 5
		Keep only the five newest session logs.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[int]$MaxAgeDays,

		[Parameter(Mandatory = $false)]
		[int]$MaxSessionFiles,

		[Parameter(Mandatory = $false)]
		[int]$MaxTotalSizeMB,

		[Parameter(Mandatory = $false)]
		[int]$MaxErrorFileSizeMB
	)

	if (-not $global:LoggingState) {
		Initialize-LoggingState | Out-Null
	}
	$state = $global:LoggingState
	if (-not (Test-Path $state.LogsDir)) { return }

	$retention = $null
	if ($state.Config -and $state.Config.FileLogging -and $state.Config.FileLogging.Retention) {
		$retention = $state.Config.FileLogging.Retention
	}

	if (-not $PSBoundParameters.ContainsKey('MaxAgeDays')) { $MaxAgeDays = if ($retention -and $null -ne $retention.MaxAgeDays) { [int]$retention.MaxAgeDays } else { 7 } }
	if (-not $PSBoundParameters.ContainsKey('MaxSessionFiles')) { $MaxSessionFiles = if ($retention -and $null -ne $retention.MaxSessionFiles) { [int]$retention.MaxSessionFiles } else { 20 } }
	if (-not $PSBoundParameters.ContainsKey('MaxTotalSizeMB')) { $MaxTotalSizeMB = if ($retention -and $null -ne $retention.MaxTotalSizeMB) { [int]$retention.MaxTotalSizeMB } else { 50 } }
	if (-not $PSBoundParameters.ContainsKey('MaxErrorFileSizeMB')) { $MaxErrorFileSizeMB = if ($retention -and $null -ne $retention.MaxErrorFileSizeMB) { [int]$retention.MaxErrorFileSizeMB } else { 5 } }

	# Only top-level session logs are eligible; Pinned/ is excluded by not recursing.
	$sessions = @(Get-ChildItem -Path $state.LogsDir -Filter "Session_*.log" -File -ErrorAction SilentlyContinue |
			Sort-Object LastWriteTime -Descending)

	# 1) Age
	if ($MaxAgeDays -gt 0) {
		$cutoff = (Get-Date).AddDays(-$MaxAgeDays)
		foreach ($file in $sessions) {
			if ($file.LastWriteTime -lt $cutoff) {
				try { Remove-Item -Path $file.FullName -Force -ErrorAction Stop } catch { }
			}
		}
		$sessions = @(Get-ChildItem -Path $state.LogsDir -Filter "Session_*.log" -File -ErrorAction SilentlyContinue |
				Sort-Object LastWriteTime -Descending)
	}

	# 2) Count (keep newest N)
	if ($MaxSessionFiles -gt 0 -and $sessions.Count -gt $MaxSessionFiles) {
		foreach ($file in ($sessions | Select-Object -Skip $MaxSessionFiles)) {
			try { Remove-Item -Path $file.FullName -Force -ErrorAction Stop } catch { }
		}
		$sessions = @(Get-ChildItem -Path $state.LogsDir -Filter "Session_*.log" -File -ErrorAction SilentlyContinue |
				Sort-Object LastWriteTime -Descending)
	}

	# 3) Total size (remove oldest until under cap)
	if ($MaxTotalSizeMB -gt 0) {
		$capBytes = [int64]$MaxTotalSizeMB * 1MB
		$total = ($sessions | Measure-Object -Property Length -Sum).Sum
		if ($null -eq $total) { $total = 0 }
		$ordered = @($sessions | Sort-Object LastWriteTime)  # oldest first
		$index = 0
		while ($total -gt $capBytes -and $index -lt $ordered.Count) {
			$victim = $ordered[$index]
			try {
				Remove-Item -Path $victim.FullName -Force -ErrorAction Stop
				$total -= $victim.Length
			}
			catch { }
			$index++
		}
	}

	# Error log: trim to the most recent content if it exceeds its cap.
	if ($MaxErrorFileSizeMB -gt 0 -and (Test-Path $state.ErrorFile)) {
		try {
			$errInfo = Get-Item -Path $state.ErrorFile -ErrorAction Stop
			if ($errInfo.Length -gt ([int64]$MaxErrorFileSizeMB * 1MB)) {
				$keep = Get-Content -Path $state.ErrorFile -Tail 2000 -ErrorAction Stop
				Set-Content -Path $state.ErrorFile -Value $keep -Encoding UTF8 -ErrorAction Stop
			}
		}
		catch { }
	}
}
