function Write-WorkspaceBenchmark {
	<#
	.SYNOPSIS
		Records how long one workspace open took and where the time went.

	.DESCRIPTION
		Appends one row to the workspace benchmark file (Get-WorkspaceBenchmarkPath) and prints a
		one-line "Timing =>" summary. Open-Workspace calls it once per workspace with the seconds
		each configured action took and the phase record Set-WorkspaceWindowLayout published
		(Get-WorkspaceLayoutTimings in the Window module), so the numbers a change is judged by
		are measured rather than read off a stopwatch.

		The row carries the timestamp, workspace, mode (Plain or Alongside), the layout outcome and
		attempt count, the total, the seconds spent in the launch actions, in the layout action as
		a whole, in each layout phase (Preamble, Desktops, FancyZones, Wait, Normalize, Position,
		Snap, Verify, Retry, Save), the remainder (OtherSeconds - the open's own bookkeeping) and the
		per-action breakdown as Name=seconds pairs. Numbers are written culture-invariant so the
		file reads the same on every machine.

		The summary line lists the phases above 0.05 s, plus "retries N" when the layout needed
		more than one attempt and the outcome when it is not Applied. Writing is best-effort: a
		failure warns and never fails the open.

	.PARAMETER Workspace
		Workspace the row describes.

	.PARAMETER TotalSeconds
		Wall-clock seconds of the whole open, as measured by the caller.

	.PARAMETER ActionTimings
		Objects with Action and Seconds, one per executed action, in execution order. The action
		named Set-WorkspaceWindowLayout - and its early preparation, timed by Open-Workspace as
		"Set-WorkspaceWindowLayout -PrepareOnly" - is reported as LayoutSeconds, every other one
		adds to ActionsSeconds.

	.PARAMETER LayoutTimings
		The record returned by Get-WorkspaceLayoutTimings. Omit when no layout ran; the row then
		reads NoLayout with every phase at 0.

	.PARAMETER Alongside
		Marks the row as an alongside open.

	.PARAMETER BenchmarkPath
		Write to a different file. Defaults to Get-WorkspaceBenchmarkPath.

	.PARAMETER Quiet
		Do not print the "Timing =>" summary line.

	.PARAMETER PassThru
		Also return the row that was written.

	.EXAMPLE
		Write-WorkspaceBenchmark -Workspace MyWorkspace -TotalSeconds 27.5 `
			-ActionTimings @(@{ Action = 'Open-Project'; Seconds = 0.4 }, @{ Action = 'Set-WorkspaceWindowLayout'; Seconds = 25.9 }) `
			-LayoutTimings (Get-WorkspaceLayoutTimings)
		# What Open-Workspace does at the end of every workspace.

	.EXAMPLE
		$row = Write-WorkspaceBenchmark -Workspace MyWorkspace -TotalSeconds 5.3 -Quiet -PassThru
		$row.OtherSeconds
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Workspace,

		[Parameter()]
		[double]$TotalSeconds = 0,

		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[object[]]$ActionTimings,

		[Parameter()]
		[AllowNull()]
		[object]$LayoutTimings,

		[Parameter()]
		[switch]$Alongside,

		[Parameter()]
		[string]$BenchmarkPath,

		[Parameter()]
		[switch]$Quiet,

		[Parameter()]
		[switch]$PassThru
	)

	$layoutActionName = 'Set-WorkspaceWindowLayout'
	$phaseNames = @('Preamble', 'Desktops', 'FancyZones', 'Wait', 'Normalize', 'Position', 'Snap', 'Verify', 'Retry', 'Save')
	$invariant = [System.Globalization.CultureInfo]::InvariantCulture

	# The launch actions and the layout action are reported apart: the layout action is the one
	# the phase columns break down further.
	$actionsSeconds = 0.0
	$layoutSeconds = 0.0
	$actionParts = [System.Collections.Generic.List[string]]::new()
	foreach ($timing in @($ActionTimings)) {
		if ($null -eq $timing) { continue }
		$actionName = [string]$timing.Action
		if ([string]::IsNullOrWhiteSpace($actionName)) { continue }

		$seconds = 0.0
		try { $seconds = [double]$timing.Seconds } catch { $seconds = 0.0 }

		# The early preparation is timed as "Set-WorkspaceWindowLayout -PrepareOnly": layout
		# work, not a launch action.
		if ($actionName -eq $layoutActionName -or $actionName -like "$layoutActionName -*") { $layoutSeconds += $seconds } else { $actionsSeconds += $seconds }
		$actionParts.Add("$actionName=$(([math]::Round($seconds, 2)).ToString('0.##', $invariant))")
	}

	$phaseSeconds = [ordered]@{}
	foreach ($phaseName in $phaseNames) { $phaseSeconds[$phaseName] = 0.0 }
	$attempts = 0
	$outcome = 'NoLayout'
	if ($null -ne $LayoutTimings) {
		if ($LayoutTimings.Phases) {
			foreach ($phaseName in $phaseNames) {
				$value = $LayoutTimings.Phases[$phaseName]
				if ($null -ne $value) {
					try { $phaseSeconds[$phaseName] = [double]$value } catch { $phaseSeconds[$phaseName] = 0.0 }
				}
			}
		}
		if ($null -ne $LayoutTimings.Attempts) {
			try { $attempts = [int]$LayoutTimings.Attempts } catch { $attempts = 0 }
		}
		if (-not [string]::IsNullOrWhiteSpace([string]$LayoutTimings.Outcome)) {
			$outcome = [string]$LayoutTimings.Outcome
		}
	}

	$otherSeconds = [math]::Max(0.0, $TotalSeconds - $actionsSeconds - $layoutSeconds)

	$row = [ordered]@{
		Timestamp         = [DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss', $invariant)
		Workspace         = $Workspace
		Mode              = if ($Alongside) { 'Alongside' } else { 'Plain' }
		Outcome           = $outcome
		Attempts          = $attempts
		TotalSeconds      = [math]::Round($TotalSeconds, 2)
		ActionsSeconds    = [math]::Round($actionsSeconds, 2)
		LayoutSeconds     = [math]::Round($layoutSeconds, 2)
		PreambleSeconds   = [math]::Round($phaseSeconds['Preamble'], 2)
		DesktopsSeconds   = [math]::Round($phaseSeconds['Desktops'], 2)
		FancyZonesSeconds = [math]::Round($phaseSeconds['FancyZones'], 2)
		WaitSeconds       = [math]::Round($phaseSeconds['Wait'], 2)
		NormalizeSeconds  = [math]::Round($phaseSeconds['Normalize'], 2)
		PositionSeconds   = [math]::Round($phaseSeconds['Position'], 2)
		SnapSeconds       = [math]::Round($phaseSeconds['Snap'], 2)
		VerifySeconds     = [math]::Round($phaseSeconds['Verify'], 2)
		RetrySeconds      = [math]::Round($phaseSeconds['Retry'], 2)
		SaveSeconds       = [math]::Round($phaseSeconds['Save'], 2)
		OtherSeconds      = [math]::Round($otherSeconds, 2)
		Actions           = ($actionParts -join ';')
	}
	$rowObject = [PSCustomObject]$row

	# The CSV copy carries every number as a culture-invariant string: a double formatted under
	# a comma-decimal culture would otherwise write "27,5" and read back as text.
	$csvRow = [ordered]@{}
	foreach ($key in $row.Keys) {
		$value = $row[$key]
		$csvRow[$key] = if ($value -is [double]) { $value.ToString('0.##', $invariant) } elseif ($value -is [int]) { $value.ToString($invariant) } else { [string]$value }
	}

	if ([string]::IsNullOrWhiteSpace($BenchmarkPath)) {
		$BenchmarkPath = Get-WorkspaceBenchmarkPath
	}

	try {
		$directory = Split-Path -Path $BenchmarkPath -Parent
		if ($directory -and -not (Test-Path -LiteralPath $directory)) {
			New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null
		}
		[PSCustomObject]$csvRow | Export-Csv -LiteralPath $BenchmarkPath -Append -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
	}
	catch {
		# Never fail an open because a measurement could not be stored.
		Write-LogWarning "Could not write the workspace benchmark row: $($_.Exception.Message)" -NoLeadingNewline
	}

	if (-not $Quiet) {
		$summaryParts = [System.Collections.Generic.List[string]]::new()
		$formatPart = { param($Label, $Seconds) "$Label $(([math]::Round([double]$Seconds, 1)).ToString('0.0', $invariant))s" }

		if ($actionsSeconds -ge 0.05) { $summaryParts.Add((& $formatPart 'actions' $actionsSeconds)) }
		foreach ($phaseName in $phaseNames) {
			if ($phaseSeconds[$phaseName] -ge 0.05) { $summaryParts.Add((& $formatPart $phaseName.ToLower() $phaseSeconds[$phaseName])) }
		}
		if ($otherSeconds -ge 0.05) { $summaryParts.Add((& $formatPart 'other' $otherSeconds)) }
		if ($attempts -gt 1) { $summaryParts.Add("retries $($attempts - 1)") }
		if ($outcome -notin @('Applied', 'NoLayout')) { $summaryParts.Add("outcome $outcome") }

		$summary = if ($summaryParts.Count -gt 0) { $summaryParts -join ' | ' } else { 'no phases recorded' }
		Write-LogStep " Timing [$Workspace] => $summary"
	}

	if ($PassThru) {
		return $rowObject
	}
}
