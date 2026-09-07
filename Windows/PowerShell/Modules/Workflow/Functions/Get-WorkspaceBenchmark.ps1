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
		Format-Table with the columns of interest - or pass -Formatted, which renders the standard
		columns (Timestamp, Attempts, Outcome, TotalSeconds, ActionsSeconds, FancyZonesSeconds,
		WaitSeconds, PositionSeconds, SnapSeconds) as an auto-sized table, and the summary table
		when combined with -Summary. Open-Workspace shows exactly that table at the end of an open
		when Configuration.WorkspaceBenchmark.Display is "Table". Warns and returns nothing when no
		run has been recorded yet.

	.PARAMETER Workspace
		One or more workspace names to keep. Omit for every workspace.

	.PARAMETER Last
		Number of most recent runs to return, after filtering. 10 by default; 0 returns all.

	.PARAMETER Summary
		Aggregate per workspace and mode instead of returning the raw rows.

	.PARAMETER Formatted
		Render the result as a table instead of returning objects: the standard columns for rows
		(Timestamp, Attempts, Outcome, TotalSeconds, ActionsSeconds, FancyZonesSeconds, WaitSeconds,
		PositionSeconds, SnapSeconds), every column for -Summary, both auto-sized.

	.PARAMETER BenchmarkPath
		Read a different benchmark file. Defaults to Get-WorkspaceBenchmarkPath.

	.EXAMPLE
		Get-WorkspaceBenchmark -Workspace MyWorkspace -Formatted
		# The last ten opens of one workspace as a table - what Open-Workspace shows after an open.

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
		[switch]$Formatted,

		[Parameter()]
		[string]$BenchmarkPath
	)

	Write-LogTitle "Workspace Benchmark"

	if ([string]::IsNullOrWhiteSpace($BenchmarkPath)) {
		$BenchmarkPath = Get-WorkspaceBenchmarkPath
	}

	if (-not (Test-Path -LiteralPath $BenchmarkPath)) {
		Write-LogWarning "No workspace benchmark recorded yet - open a workspace first (expected file => [$BenchmarkPath])"
		return
	}

	# The typed read (culture-invariant numbers, chronological order) lives in
	# Read-WorkspaceBenchmark so Measure-WorkspaceOpen reads exactly the same rows.
	$rows = @()
	try {
		$rows = @(Read-WorkspaceBenchmark -BenchmarkPath $BenchmarkPath)
	}
	catch {
		Write-LogWarning "Could not read the workspace benchmark file [$BenchmarkPath]: $($_.Exception.Message)"
		return
	}

	if ($Workspace) {
		$rows = @($rows | Where-Object { $Workspace -contains $_.Workspace })
	}

	if ($Last -gt 0 -and $rows.Count -gt $Last) {
		$rows = @($rows | Select-Object -Last $Last)
	}

	if (-not $Summary) {
		if ($Formatted) {
			return ($rows | Format-Table -Property Timestamp, Attempts, Outcome, TotalSeconds, ActionsSeconds, FancyZonesSeconds, WaitSeconds, PositionSeconds, SnapSeconds -AutoSize)
		}
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

	if ($Formatted) {
		return (@($summaries) | Format-Table -AutoSize)
	}
	return @($summaries)
}
