function Get-WorkspaceBenchmark {
	<#
	.SYNOPSIS
		Reads the workspace benchmark back - one row per workspace open, or a per-workspace summary.

	.DESCRIPTION
		Returns the runs Write-WorkspaceBenchmark recorded in WorkspaceBenchmark.csv
		(Get-WorkspaceBenchmarkPath) as objects with typed numbers, oldest first: one row per open
		with the total, the seconds the launch actions took, and the seconds Set-WorkspaceWindowLayout
		spent in each phase (Preamble, Desktops, FancyZones, Wait, Normalize, Position, Snap, Verify,
		Retry, Save), the attempt count and the outcome. This is what a change to the open flow is
		judged by: run the same workspace a few times before and after, compare the phase columns,
		and read Attempts and Outcome first - a saving that arrives with retries is not a saving.

		-Workspace keeps one or more workspaces, -Last bounds the result to the most recent N runs
		after filtering (10 by default, 0 for all), and -Summary aggregates instead: per workspace
		and mode, the number of runs, average/min/max total, the average of every phase, the retries
		and the runs that did not end Applied.

		The rows have more columns than PowerShell shows as a table by default, so pipe them to
		Format-Table with the columns of interest. Warns and returns nothing when no run has been
		recorded yet.

	.PARAMETER Workspace
		One or more workspace names to keep. Omit for every workspace.

	.PARAMETER Last
		Number of most recent runs to return, after filtering. 10 by default; 0 returns all.

	.PARAMETER Summary
		Aggregate per workspace and mode instead of returning the raw rows.

	.PARAMETER BenchmarkPath
		Read a different benchmark file. Defaults to Get-WorkspaceBenchmarkPath.

	.EXAMPLE
		Get-WorkspaceBenchmark | Format-Table -AutoSize
		# The last ten opens, one row each.

	.EXAMPLE
		Get-WorkspaceBenchmark -Workspace MyWorkspace -Last 20 | Format-Table Timestamp, Attempts, TotalSeconds, ActionsSeconds, FancyZonesSeconds, WaitSeconds, PositionSeconds, SnapSeconds
		# Before/after comparison for one workspace.

	.EXAMPLE
		Get-WorkspaceBenchmark -Summary | Format-Table -AutoSize
		# Averages per workspace and mode.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Position = 0)]
		[string[]]$Workspace,

		[Parameter()]
		[ValidateRange(0, [int]::MaxValue)]
		[int]$Last = 10,

		[Parameter()]
		[switch]$Summary,

		[Parameter()]
		[string]$BenchmarkPath
	)

	if ([string]::IsNullOrWhiteSpace($BenchmarkPath)) {
		$BenchmarkPath = Get-WorkspaceBenchmarkPath
	}

	if (-not (Test-Path -LiteralPath $BenchmarkPath)) {
		Write-LogWarning "No workspace benchmark recorded yet - open a workspace first (expected file => [$BenchmarkPath])"
		return
	}

	$rawRows = @()
	try {
		$rawRows = @(Import-Csv -LiteralPath $BenchmarkPath -ErrorAction Stop)
	}
	catch {
		Write-LogWarning "Could not read the workspace benchmark file [$BenchmarkPath]: $($_.Exception.Message)"
		return
	}

	$integerColumns = @('Attempts')
	$secondColumns = @(
		'TotalSeconds', 'ActionsSeconds', 'LayoutSeconds', 'PreambleSeconds', 'DesktopsSeconds',
		'FancyZonesSeconds', 'WaitSeconds', 'NormalizeSeconds', 'PositionSeconds', 'SnapSeconds',
		'VerifySeconds', 'RetrySeconds', 'SaveSeconds', 'OtherSeconds'
	)
	$invariant = [System.Globalization.CultureInfo]::InvariantCulture

	# Import-Csv yields strings; the numbers were written culture-invariant, so they parse the
	# same way everywhere. An unparseable cell reads as 0 rather than failing the whole read.
	$rows = foreach ($rawRow in $rawRows) {
		$typed = [ordered]@{}
		foreach ($property in $rawRow.PSObject.Properties) {
			$name = $property.Name
			$value = $property.Value

			if ($secondColumns -contains $name -or $integerColumns -contains $name) {
				$parsed = 0.0
				if (-not [double]::TryParse([string]$value, [System.Globalization.NumberStyles]::Float, $invariant, [ref]$parsed)) {
					$parsed = 0.0
				}
				$value = if ($integerColumns -contains $name) { [int]$parsed } else { [double]$parsed }
			}

			$typed[$name] = $value
		}
		[PSCustomObject]$typed
	}
	$rows = @($rows)

	if ($Workspace) {
		$rows = @($rows | Where-Object { $Workspace -contains $_.Workspace })
	}

	# Timestamps are written as yyyy-MM-dd HH:mm:ss, so a string sort is chronological. -Stable
	# keeps rows written within the same second in file order.
	$rows = @($rows | Sort-Object -Property Timestamp -Stable)

	if ($Last -gt 0 -and $rows.Count -gt $Last) {
		$rows = @($rows | Select-Object -Last $Last)
	}

	if (-not $Summary) {
		return $rows
	}

	$average = {
		param($Items, [string]$Property)
		if (-not $Items -or @($Items).Count -eq 0) { return 0.0 }
		$measured = @($Items) | Measure-Object -Property $Property -Average
		return [math]::Round([double]$measured.Average, 1)
	}

	$summaries = foreach ($group in ($rows | Group-Object -Property Workspace, Mode)) {
		$items = @($group.Group)
		$totals = @($items) | Measure-Object -Property TotalSeconds -Minimum -Maximum

		[PSCustomObject]@{
			Workspace     = $items[0].Workspace
			Mode          = $items[0].Mode
			Runs          = $items.Count
			AvgTotal      = & $average $items 'TotalSeconds'
			MinTotal      = [math]::Round([double]$totals.Minimum, 1)
			MaxTotal      = [math]::Round([double]$totals.Maximum, 1)
			AvgActions    = & $average $items 'ActionsSeconds'
			AvgFancyZones = & $average $items 'FancyZonesSeconds'
			AvgWait       = & $average $items 'WaitSeconds'
			AvgPosition   = & $average $items 'PositionSeconds'
			AvgSnap       = & $average $items 'SnapSeconds'
			AvgVerify     = & $average $items 'VerifySeconds'
			AvgOther      = & $average $items 'OtherSeconds'
			Retries       = [int](@($items | ForEach-Object { [math]::Max(0, [int]$_.Attempts - 1) }) | Measure-Object -Sum).Sum
			NotApplied    = @($items | Where-Object { $_.Outcome -notin @('Applied', 'NoLayout') }).Count
			LastRun       = $items[-1].Timestamp
		}
	}

	return @($summaries)
}
