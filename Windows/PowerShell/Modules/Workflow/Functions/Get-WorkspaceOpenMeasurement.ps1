function Get-WorkspaceOpenMeasurement {
	<#
	.SYNOPSIS
		Replays the summary table of a Measure-WorkspaceOpen session from the result file, or lists the sessions.

	.DESCRIPTION
		Measure-WorkspaceOpen prints its per-variant table once, at the end of a run that took ten
		minutes or more; when the scrollback is gone the table is gone with it. This function
		rebuilds it from WorkspaceOpenMeasurements.csv (Get-WorkspaceOpenMeasurementPath) with the
		same arithmetic (ConvertTo-WorkspaceOpenSummary), so the replayed table says exactly what
		the live run said: one row per variant with runs, Clean, Retries, NotApplied, the medians,
		and Effect/Spread/Verdict against the reference variant.

		Without -Session the most recent session is summarized. -ListSessions instead returns one
		row per recorded session - id, workspace, project, when it started, how many opens and
		variants it had - so the id of an older run can be found. -Formatted renders the result as
		an auto-sized table instead of returning objects; -PassThru returns a single object with
		Summary and Runs (the typed per-run rows) for your own analysis.

		Warns and returns nothing when no experiment has been recorded yet.

	.PARAMETER Session
		The session id to summarize (the yyyyMMdd-HHmmss stamp Measure-WorkspaceOpen printed).
		The most recent session by default.

	.PARAMETER ListSessions
		Return one row per recorded session instead of a summary.

	.PARAMETER Reference
		The variant the others are compared with. The first variant that ran by default.

	.PARAMETER Formatted
		Render the result as an auto-sized table instead of returning objects.

	.PARAMETER PassThru
		Return one object with Summary and Runs (the typed per-run rows of the session).

	.PARAMETER ResultPath
		Read a different file. Defaults to Get-WorkspaceOpenMeasurementPath.

	.EXAMPLE
		Get-WorkspaceOpenMeasurement -Formatted
		# The table of the most recent experiment.

	.EXAMPLE
		Get-WorkspaceOpenMeasurement -ListSessions -Formatted
		Get-WorkspaceOpenMeasurement -Session 20260907-135804 -Formatted

	.EXAMPLE
		(Get-WorkspaceOpenMeasurement -PassThru).Runs | Format-Table Variant, Round, Outcome, Attempts, TotalSeconds
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Position = 0)]
		[string]$Session,

		[Parameter()]
		[switch]$ListSessions,

		[Parameter()]
		[string]$Reference,

		[Parameter()]
		[switch]$Formatted,

		[Parameter()]
		[switch]$PassThru,

		[Parameter()]
		[string]$ResultPath
	)

	Write-LogTitle "Workspace Open Measurement"

	if ([string]::IsNullOrWhiteSpace($ResultPath)) {
		$ResultPath = Get-WorkspaceOpenMeasurementPath
	}

	if (-not (Test-Path -LiteralPath $ResultPath)) {
		Write-LogWarning "No experiment recorded yet - run Measure-WorkspaceOpen first (expected file => [$ResultPath])"
		return
	}

	$rows = @()
	try {
		$rows = @(Read-WorkspaceOpenMeasurement -ResultPath $ResultPath)
	}
	catch {
		Write-LogWarning "Could not read the measurement file [$ResultPath]: $($_.Exception.Message)"
		return
	}
	if ($rows.Count -eq 0) {
		Write-LogWarning "The measurement file [$ResultPath] has no rows."
		return
	}

	if ($ListSessions) {
		$sessions = foreach ($group in ($rows | Group-Object -Property Session | Sort-Object -Property Name)) {
			$items = @($group.Group)
			[PSCustomObject]@{
				Session   = $group.Name
				Workspace = [string]$items[0].Workspace
				Project   = [string]$items[0].Project
				Started   = [string]($items | Sort-Object -Property Position | Select-Object -First 1).Timestamp
				Opens     = $items.Count
				Measured  = @($items | Where-Object { $_.Measured }).Count
				Variants  = @($items | Where-Object { $_.Measured } | Select-Object -ExpandProperty Variant -Unique).Count
			}
		}
		$sessions = @($sessions)
		if ($Formatted) { return ($sessions | Format-Table -AutoSize) }
		return $sessions
	}

	if ([string]::IsNullOrWhiteSpace($Session)) {
		$Session = @($rows | Select-Object -ExpandProperty Session | Sort-Object)[-1]
	}
	$sessionRows = @($rows | Where-Object { $_.Session -eq $Session })
	if ($sessionRows.Count -eq 0) {
		Write-LogWarning "No session [$Session] in [$ResultPath] - Get-WorkspaceOpenMeasurement -ListSessions shows the recorded ones."
		return
	}

	$summaryArguments = @{ Row = $sessionRows }
	if (-not [string]::IsNullOrWhiteSpace($Reference)) { $summaryArguments['Reference'] = $Reference }
	$summaries = @(ConvertTo-WorkspaceOpenSummary @summaryArguments)

	$workspaceLabel = [string]$sessionRows[0].Workspace
	if (-not [string]::IsNullOrWhiteSpace([string]$sessionRows[0].Project)) { $workspaceLabel += " -Project $($sessionRows[0].Project)" }
	Write-LogStep " Session [$Session] => [$workspaceLabel], $($sessionRows.Count) open(s), $($summaries.Count) variant(s)"

	if ($Formatted) {
		return ($summaries | Format-Table -Property Variant, Runs, Clean, Retries, NotApplied, MedianTotal, CleanMedianTotal, MinTotal, MaxTotal, Effect, Spread, Verdict, MedianLayout, MedianFancyZones, MedianWait, MedianPositionSnap, MedianVerify -AutoSize)
	}
	if ($PassThru) {
		return [PSCustomObject]@{ Session = $Session; Summary = $summaries; Runs = $sessionRows }
	}
	return $summaries
}
