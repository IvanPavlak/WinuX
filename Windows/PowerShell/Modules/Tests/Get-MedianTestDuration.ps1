function Get-MedianTestDuration {
	<#
	.SYNOPSIS
		The median milliseconds per test across every file with a measured timing.

	.DESCRIPTION
		Invoke-TestSuite seeds the bucketing weight of a file that has no timings.json entry yet
		from this median, multiplied by the file's statically counted tests. A median, not a
		mean: the few real-git files are orders of magnitude slower per test than the rest and
		would drag a mean far away from what an ordinary new file costs.

		Pure: reads nothing, writes nothing. A plain script beside Invoke-TestSuite (not an
		exported function) because the orchestrator runs with zero WinuX modules loaded in CI.

	.PARAMETER Timings
		The parsed timings.json: a hashtable of relative path to an object with ms and tests.

	.OUTPUTS
		[double] The median, or 0 when no entry has both a duration and a test count.

	.EXAMPLE
		$medianMs = Get-MedianTestDuration -Timings $timings
	#>
	[CmdletBinding()]
	[OutputType([double])]
	param(
		[Parameter(Mandatory = $true)]
		[AllowNull()]
		[hashtable]$Timings
	)

	if (-not $Timings) { return 0.0 }

	$perTest = @(
		foreach ($entry in $Timings.Values) {
			if ($entry -and $entry.ms -and $entry.tests -and [double]$entry.tests -gt 0) {
				[double]$entry.ms / [double]$entry.tests
			}
		}
	) | Sort-Object
	$perTest = @($perTest)

	if ($perTest.Count -eq 0) { return 0.0 }
	$middle = [int][math]::Floor($perTest.Count / 2)
	if ($perTest.Count % 2 -eq 1) { return [double]$perTest[$middle] }
	return ([double]$perTest[$middle - 1] + [double]$perTest[$middle]) / 2.0
}
