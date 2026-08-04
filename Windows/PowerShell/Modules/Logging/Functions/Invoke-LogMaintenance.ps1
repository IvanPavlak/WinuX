function Invoke-LogMaintenance {
	<#
	.SYNOPSIS
		Runs the periodic, silent housekeeping sweep over every log the repository generates.

	.DESCRIPTION
		Single entry point for background log hygiene. Enforces session-log retention via
		Clear-OldLogs (limits from $Configuration.Logging.FileLogging.Retention), then prunes the
		Tests\Results folder with the same rules Invoke-TestSuite applies at run start: the ten
		newest TestRun_*.log files are kept, orphaned pester-results-*.xml files (whose owning run
		log is gone) are removed, and abandoned Work\ directories are swept. Results artifacts are
		only touched when older than one day, so a test run in flight can never lose its files.
		timings.json, .gitkeep files, and Logs/Pinned are never touched.

		Produces no console output and swallows per-file errors, so it is safe to call from the
		profile's idle-time hook. Throttled by a stamp file (Logs\.last-maintenance): when the last
		sweep is younger than Maintenance.IntervalHours the call returns immediately (~1 ms), so
		opening many shells per day costs nothing. Behavior defaults from
		$Configuration.Logging.Maintenance (Enabled $true, IntervalHours 24) - runs out of the box,
		set Enabled = $false to opt out. Called automatically once per interval from the profile's
		PowerShell.OnIdle hook; safe to run manually at any time.

	.PARAMETER Force
		Run the sweep now, ignoring the Enabled flag and the stamp-file throttle.

	.PARAMETER ResultsDirectory
		Override the Tests\Results directory to prune (default: resolved via Get-RepositoryPath).
		Intended for tests.

	.EXAMPLE
		Invoke-LogMaintenance
		Runs the sweep if the maintenance interval has elapsed; otherwise returns immediately.

	.EXAMPLE
		Invoke-LogMaintenance -Force
		Runs the full sweep right now, regardless of the stamp file.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$Force,

		[Parameter(Mandatory = $false)]
		[string]$ResultsDirectory
	)

	$maintenance = $null
	if ($global:Configuration -and $global:Configuration.Logging -and $global:Configuration.Logging.Maintenance) {
		$maintenance = $global:Configuration.Logging.Maintenance
	}

	$enabled = if ($maintenance -and $null -ne $maintenance.Enabled) { [bool]$maintenance.Enabled } else { $true }
	$intervalHours = if ($maintenance -and $null -ne $maintenance.IntervalHours) { [int]$maintenance.IntervalHours } else { 24 }

	if (-not $enabled -and -not $Force) { return }

	if (-not $global:LoggingState) {
		Initialize-LoggingState | Out-Null
	}
	$state = $global:LoggingState
	if (-not (Test-Path $state.LogsDir)) { return }

	# Stamp throttle: skip when the last sweep is younger than the interval. The stamp is written
	# up front so concurrent shells (and a sweep that fails midway) don't re-run it back to back.
	$stampFile = Join-Path $state.LogsDir ".last-maintenance"
	if (-not $Force -and (Test-Path $stampFile)) {
		$stampAge = (Get-Date) - (Get-Item -Path $stampFile -Force).LastWriteTime
		if ($stampAge.TotalHours -lt $intervalHours) { return }
	}
	try { Set-Content -Path $stampFile -Value (Get-Date -Format 'o') -Encoding UTF8 -Force -ErrorAction Stop } catch { }

	# Session logs + error log: existing retention, limits from configuration.
	try { Clear-OldLogs } catch { }

	# Tests\Results: same shape Invoke-TestSuite enforces at run start, so the folder stays
	# bounded even on machines that stopped running the suite. Everything here is age-gated to
	# one day - a live run's artifacts (its run log appears only at the end of the run) are
	# never eligible.
	$resultsDir = $ResultsDirectory
	if (-not $resultsDir) {
		try { $resultsDir = Join-Path (Get-RepositoryPath -StartPath $PSScriptRoot).Modules "Tests\Results" } catch { return }
	}
	if (-not (Test-Path $resultsDir)) { return }

	$ageCutoff = (Get-Date).AddDays(-1)
	$retainedLogs = 10

	# 1) Keep the ten newest completed run logs (mirrors Invoke-TestSuite's own retention).
	$runLogs = @(Get-ChildItem -Path $resultsDir -Filter "TestRun_*.log" -File -ErrorAction SilentlyContinue |
			Sort-Object LastWriteTime -Descending)
	if ($runLogs.Count -gt $retainedLogs) {
		foreach ($stale in ($runLogs | Select-Object -Skip $retainedLogs)) {
			if ($stale.LastWriteTime -lt $ageCutoff) {
				try { Remove-Item -LiteralPath $stale.FullName -Force -ErrorAction Stop } catch { }
			}
		}
	}

	# 2) An XML whose run log is gone is an orphan; the age gate protects a run still in flight
	# (its XMLs exist before its run log does).
	$liveRunIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
	foreach ($log in (Get-ChildItem -Path $resultsDir -Filter "TestRun_*.log" -File -ErrorAction SilentlyContinue)) {
		[void]$liveRunIds.Add(($log.BaseName -replace '^TestRun_', ''))
	}
	foreach ($xml in (Get-ChildItem -Path $resultsDir -Filter "pester-results-*.xml" -File -ErrorAction SilentlyContinue)) {
		$owner = ($xml.BaseName -replace '^pester-results-', '') -replace '-worker\d+$', ''
		if (-not $liveRunIds.Contains($owner) -and $xml.LastWriteTime -lt $ageCutoff) {
			try { Remove-Item -LiteralPath $xml.FullName -Force -ErrorAction Stop } catch { }
		}
	}

	# 3) Work directories are removed by the run that owns them; a killed run leaves one behind.
	$workRoot = Join-Path $resultsDir "Work"
	if (Test-Path $workRoot) {
		foreach ($abandoned in (Get-ChildItem -Path $workRoot -Directory -ErrorAction SilentlyContinue)) {
			if ($abandoned.LastWriteTime -lt $ageCutoff) {
				try { Remove-Item -LiteralPath $abandoned.FullName -Recurse -Force -ErrorAction Stop } catch { }
			}
		}
	}
}
