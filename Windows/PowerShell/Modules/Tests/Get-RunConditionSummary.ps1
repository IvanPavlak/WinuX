function Get-RunConditionSummary {
	<#
	.SYNOPSIS
		Condenses the run-condition samples and the workers' start-up times into one summary.

	.DESCRIPTION
		The pure half of the run-condition sampler: everything here is arithmetic over what
		Start-RunConditionSampler collected, so it can be tested without a machine to sample.

		ForeignLoadPercent is the CPU used by processes outside the test run, minus the ones the
		run itself induces (Defender, the kernel), as a percentage of the whole machine's
		capacity over the sampled time. It is what decides whether a run was too noisy to teach
		the adaptive worker count.

	.PARAMETER Samples
		The samples, as Stop-RunConditionSampler returns them.

	.PARAMETER StartupSeconds
		Each worker's start-up time: from spawn to its first test file starting.

	.PARAMETER ProcessorCount
		[Environment]::ProcessorCount, to turn CPU milliseconds into a share of the machine.

	.PARAMETER Top
		How many foreign processes to list. Defaults to 5.

	.OUTPUTS
		[pscustomobject] SampleCount, AvgCpuPercent, MaxCpuPercent, MinPerformancePercent,
		MinAvailableMB, ForeignLoadPercent (-1 when unknown), TopConsumers (Name, CpuSeconds),
		StartupMin, StartupAvg, StartupMax (seconds; $null when unknown).

	.EXAMPLE
		Get-RunConditionSummary -Samples $samples -StartupSeconds 4.2, 5.0 -ProcessorCount 16
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[object[]]$Samples = @(),

		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[double[]]$StartupSeconds = @(),

		[Parameter(Mandatory = $true)]
		[int]$ProcessorCount,

		[Parameter()]
		[int]$Top = 5
	)

	$Samples = @($Samples | Where-Object { $_ })
	$cpuValues = @($Samples | Where-Object { $null -ne $_.CpuPercent } | ForEach-Object { [double]$_.CpuPercent })
	$performanceValues = @($Samples | Where-Object { $null -ne $_.PerformancePercent } | ForEach-Object { [double]$_.PerformancePercent })
	$memoryValues = @($Samples | Where-Object { $null -ne $_.AvailableMB } | ForEach-Object { [double]$_.AvailableMB })

	$byName = @{}
	$foreignMs = 0.0
	$intervalMs = 0.0
	foreach ($sample in $Samples) {
		$intervalMs += [double]$sample.IntervalMs
		$foreignMs += [double]$sample.ForeignMs
		if ($sample.ByName) {
			$names = if ($sample.ByName -is [System.Collections.IDictionary]) { $sample.ByName.Keys } else { $sample.ByName.PSObject.Properties.Name }
			foreach ($name in $names) {
				$value = [double]$sample.ByName.$name
				if ($byName.ContainsKey($name)) { $byName[$name] += $value } else { $byName[$name] = $value }
			}
		}
	}

	$capacityMs = $intervalMs * [Math]::Max(1, $ProcessorCount)
	$foreignLoad = if ($Samples.Count -gt 0 -and $capacityMs -gt 0) { [math]::Round(100.0 * $foreignMs / $capacityMs, 1) } else { -1.0 }

	$topConsumers = @(
		$byName.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $Top | ForEach-Object {
			[pscustomobject]@{ Name = $_.Key; CpuSeconds = [math]::Round($_.Value / 1000.0, 1) }
		}
	)

	$startups = @($StartupSeconds | Where-Object { $_ -gt 0 })
	$measure = { param([double[]]$Values, [string]$Kind)
		if ($Values.Count -eq 0) { return $null }
		$statistic = $Values | Measure-Object -Minimum -Maximum -Average
		[math]::Round([double]$statistic.$Kind, 1)
	}

	[pscustomobject]@{
		SampleCount           = $Samples.Count
		AvgCpuPercent         = & $measure $cpuValues 'Average'
		MaxCpuPercent         = & $measure $cpuValues 'Maximum'
		MinPerformancePercent = & $measure $performanceValues 'Minimum'
		MinAvailableMB        = & $measure $memoryValues 'Minimum'
		ForeignLoadPercent    = [double]$foreignLoad
		TopConsumers          = $topConsumers
		StartupMin            = & $measure $startups 'Minimum'
		StartupAvg            = & $measure $startups 'Average'
		StartupMax            = & $measure $startups 'Maximum'
	}
}
