function Get-AdaptiveWorkerCount {
	<#
	.SYNOPSIS
		Picks the worker count for a run from the wall clocks of earlier full runs on this machine.

	.DESCRIPTION
		The best worker count is machine-specific and drifts: every worker added also adds
		contention (process start-up, Defender, disk), so a fixed formula over
		[Environment]::ProcessorCount is a guess. This learns it from recorded full runs instead.

		- No history: min(ProcessorCount, DefaultCap).
		- The best count is the one with the lowest median wall clock over its last (up to) five
		  samples, among the counts that have at least two samples; a count needs two samples
		  before it can displace the default.
		- Explore: each neighbour of the best - round(best * 1.25) first, then round(best * 0.75),
		  both inside [2, ProcessorCount] - is tried once.
		- Confirm: a neighbour whose one sample beat the best is tried a second time.
		- Settle: the best is used until it has two samples, and from then on.
		- Re-check: every 20th recorded run tries one neighbour again, alternating, so a machine
		  whose best count drifts is noticed.
		- A scoped run never explores. It uses the best count, capped so that no worker gets
		  less work than its own start-up costs (MinWorkPerWorkerMs) and never more workers than
		  files: with a handful of files, start-up is most of the run.

		Pure: no file I/O, no clock. Read-WorkerHistory supplies the runs.

	.PARAMETER Runs
		The recorded runs for this machine's fingerprint, oldest first; each has workers and
		wallSec.

	.PARAMETER Recorded
		How many runs have ever been recorded for this fingerprint (drives the every-20th re-check).

	.PARAMETER ProcessorCount
		[Environment]::ProcessorCount.

	.PARAMETER FileCount
		The number of test files in this run.

	.PARAMETER TotalWeightMs
		The summed bucketing weight of this run's files.

	.PARAMETER Scoped
		The run is not a full run (a filter, -Path, -Changed or -Quick).

	.PARAMETER DefaultCap
		The no-history default is min(ProcessorCount, DefaultCap). Defaults to 12.

	.PARAMETER MinWorkPerWorkerMs
		The least work a scoped run gives each worker. Defaults to 4000.

	.OUTPUTS
		[pscustomobject] Count, Best, Phase (Default, Explore, Confirm, Settle, Recheck, Scoped), Reason.

	.EXAMPLE
		Get-AdaptiveWorkerCount -Runs $history.Runs -Recorded $history.Recorded -ProcessorCount 16 -FileCount 448 -TotalWeightMs 400000
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[object[]]$Runs = @(),

		[Parameter()]
		[int]$Recorded = 0,

		[Parameter(Mandatory = $true)]
		[int]$ProcessorCount,

		[Parameter(Mandatory = $true)]
		[int]$FileCount,

		[Parameter()]
		[double]$TotalWeightMs = 0,

		[Parameter()]
		[switch]$Scoped,

		[Parameter()]
		[int]$DefaultCap = 12,

		[Parameter()]
		[double]$MinWorkPerWorkerMs = 4000
	)

	$invariant = [System.Globalization.CultureInfo]::InvariantCulture
	$cpu = [Math]::Max(1, $ProcessorCount)
	$default = [Math]::Max(1, [Math]::Min($cpu, $DefaultCap))
	$lower = [Math]::Min(2, $cpu)

	# Per count: its samples (newest last) and the median of the newest five.
	$byCount = @{}
	foreach ($run in @($Runs | Where-Object { $_ -and [int]$_.workers -gt 0 -and [double]$_.wallSec -gt 0 })) {
		$key = [int]$run.workers
		if (-not $byCount.ContainsKey($key)) { $byCount[$key] = [System.Collections.Generic.List[double]]::new() }
		$byCount[$key].Add([double]$run.wallSec)
	}
	$stats = @{}
	foreach ($key in $byCount.Keys) {
		$recent = @($byCount[$key] | Select-Object -Last 5 | Sort-Object)
		$middle = [int][math]::Floor($recent.Count / 2)
		$median = if ($recent.Count % 2 -eq 1) { $recent[$middle] } else { ($recent[$middle - 1] + $recent[$middle]) / 2.0 }
		$stats[$key] = [pscustomobject]@{ Samples = $byCount[$key].Count; Median = [double]$median }
	}

	$best = $default
	$bestMedian = [double]::PositiveInfinity
	if ($stats.ContainsKey($default) -and $stats[$default].Samples -ge 2) { $bestMedian = $stats[$default].Median }
	foreach ($key in ($stats.Keys | Sort-Object)) {
		if ($stats[$key].Samples -ge 2 -and $stats[$key].Median -lt $bestMedian) {
			$best = $key
			$bestMedian = $stats[$key].Median
		}
	}

	$capToFiles = { param([int]$Count) [Math]::Max(1, [Math]::Min($Count, [Math]::Max(1, $FileCount))) }
	$result = {
		param([int]$Count, [string]$Phase, [string]$Reason)
		[pscustomobject]@{ Count = (& $capToFiles $Count); Best = $best; Phase = $Phase; Reason = $Reason }
	}

	if ($Scoped) {
		$byWork = if ($MinWorkPerWorkerMs -gt 0 -and $TotalWeightMs -gt 0) { [int][math]::Ceiling($TotalWeightMs / $MinWorkPerWorkerMs) } else { $best }
		$count = [Math]::Max(1, [Math]::Min($best, $byWork))
		return & $result $count 'Scoped' ([string]::Format($invariant, "scoped run: best {0}, capped by {1:N1}s of work at {2:N1}s per worker", $best, ($TotalWeightMs / 1000.0), ($MinWorkPerWorkerMs / 1000.0)))
	}

	if ($stats.Count -eq 0) {
		return & $result $default 'Default' "no history: min(CPU $cpu, $DefaultCap)"
	}

	$neighbours = [System.Collections.Generic.List[int]]::new()
	foreach ($factor in 1.25, 0.75) {
		$candidate = [int][math]::Round($best * $factor, [MidpointRounding]::AwayFromZero)
		$candidate = [Math]::Max($lower, [Math]::Min($cpu, $candidate))
		if ($candidate -ne $best -and -not $neighbours.Contains($candidate)) { $neighbours.Add($candidate) }
	}

	foreach ($neighbour in $neighbours) {
		if (-not $stats.ContainsKey($neighbour)) {
			return & $result $neighbour 'Explore' "exploring neighbour $neighbour of best $best"
		}
	}

	$bestSamples = if ($stats.ContainsKey($best)) { $stats[$best].Samples } else { 0 }
	$bestKnown = if ($stats.ContainsKey($best)) { $stats[$best].Median } else { [double]::PositiveInfinity }
	foreach ($neighbour in $neighbours) {
		if ($stats[$neighbour].Samples -eq 1 -and $stats[$neighbour].Median -lt $bestKnown) {
			return & $result $neighbour 'Confirm' ([string]::Format($invariant, "confirming neighbour {0} ({1:N1}s) against best {2}", $neighbour, $stats[$neighbour].Median, $best))
		}
	}

	if ($bestSamples -lt 2) {
		return & $result $best 'Settle' "second sample for best $best"
	}

	if ($Recorded -gt 0 -and $Recorded % 20 -eq 0 -and $neighbours.Count -gt 0) {
		$neighbour = $neighbours[[int](($Recorded / 20) % $neighbours.Count)]
		return & $result $neighbour 'Recheck' "periodic re-check of neighbour $neighbour (run $Recorded)"
	}

	return & $result $best 'Settle' ([string]::Format($invariant, "learned best {0} (median {1:N1}s over {2} run(s))", $best, $bestMedian, $bestSamples))
}
