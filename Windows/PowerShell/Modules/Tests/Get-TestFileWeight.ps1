function Get-TestFileWeight {
	<#
	.SYNOPSIS
		The expected duration, in milliseconds, that Invoke-TestSuite buckets a test file by.

	.DESCRIPTION
		In order of preference:

		1. The file's measured duration from the previous run (its timings.json entry).
		2. A file tagged Integration that has never been measured gets a fixed heavy seed, so a
		   new real-git file is never stacked on top of other heavy files on its first run.
		3. Otherwise its statically counted tests times the median known milliseconds per test,
		   plus a fixed per-file discovery cost.
		4. On a cold checkout with no timings at all, file size stands in: the suite averages
		   roughly 15 bytes of test source per millisecond, plus the same per-file cost.

		Pure. A plain script beside Invoke-TestSuite for the same reason as Get-ExpectedTestCount.

	.PARAMETER Timing
		The file's timings.json entry (an object with ms and tests), or $null when it has none.

	.PARAMETER ExpectedCount
		The file's statically counted tests (Get-ExpectedTestCount).

	.PARAMETER IsIntegration
		Whether the file carries the Integration tag.

	.PARAMETER FileBytes
		The file's size, for the cold-checkout fallback.

	.PARAMETER MedianMsPerTest
		Get-MedianTestDuration over the known timings; 0 when nothing is known.

	.PARAMETER IntegrationSeedMs
		The weight of a never-measured Integration file. Defaults to 60 seconds.

	.OUTPUTS
		[double] The weight in milliseconds.

	.EXAMPLE
		Get-TestFileWeight -Timing $null -ExpectedCount 12 -MedianMsPerTest 85
	#>
	[CmdletBinding()]
	[OutputType([double])]
	param(
		[Parameter()]
		[AllowNull()]
		[object]$Timing,

		[Parameter()]
		[int]$ExpectedCount = 0,

		[Parameter()]
		[bool]$IsIntegration = $false,

		[Parameter()]
		[long]$FileBytes = 0,

		[Parameter()]
		[double]$MedianMsPerTest = 0,

		[Parameter()]
		[double]$IntegrationSeedMs = 60000
	)

	$perFileMs = 150.0

	if ($Timing -and $Timing.ms -and [double]$Timing.ms -gt 0) { return [double]$Timing.ms }
	if ($IsIntegration) { return $IntegrationSeedMs }
	if ($MedianMsPerTest -gt 0 -and $ExpectedCount -gt 0) { return $perFileMs + ($ExpectedCount * $MedianMsPerTest) }
	return $perFileMs + ($FileBytes / 15.0)
}
