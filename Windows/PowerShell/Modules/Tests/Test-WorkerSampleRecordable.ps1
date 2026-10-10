function Test-WorkerSampleRecordable {
	<#
	.SYNOPSIS
		Decides whether a finished run may teach the adaptive worker count.

	.DESCRIPTION
		Only full, green, representative runs teach. A run is not recorded when it was a CI run,
		used an explicit -Workers, was scoped (a filter, -Path, -Changed or -Quick), had a failing
		test or an infrastructure failure, or ran while something else loaded the machine: when
		processes outside the test run used more than MaxForeignLoadPercent of the machine's CPU,
		its wall clock says more about that load than about the worker count. An unknown load
		(the sampler could not read the machine) does not block recording.

		Pure.

	.PARAMETER CI
		The run was a -CI run.

	.PARAMETER ExplicitWorkers
		The worker count came from -Workers, not from the learner.

	.PARAMETER Scoped
		The run was not the full suite.

	.PARAMETER FailedCount
		Failed tests.

	.PARAMETER InfrastructureError
		The run did not complete cleanly (exit code 2).

	.PARAMETER ForeignLoadPercent
		Average CPU used by processes outside the test run, as a percentage of the whole machine;
		a negative value means unknown.

	.PARAMETER MaxForeignLoadPercent
		The foreign load above which a run is too noisy to record. Defaults to 15.

	.OUTPUTS
		[pscustomobject] Recordable (bool), Reason (string).

	.EXAMPLE
		Test-WorkerSampleRecordable -FailedCount 0 -ForeignLoadPercent 3.2
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter()]
		[switch]$CI,

		[Parameter()]
		[switch]$ExplicitWorkers,

		[Parameter()]
		[switch]$Scoped,

		[Parameter()]
		[int]$FailedCount = 0,

		[Parameter()]
		[switch]$InfrastructureError,

		[Parameter()]
		[double]$ForeignLoadPercent = -1,

		[Parameter()]
		[double]$MaxForeignLoadPercent = 15
	)

	$verdict = { param([bool]$Recordable, [string]$Reason) [pscustomobject]@{ Recordable = $Recordable; Reason = $Reason } }

	if ($CI) { return & $verdict $false 'CI run' }
	if ($ExplicitWorkers) { return & $verdict $false 'explicit -Workers' }
	if ($Scoped) { return & $verdict $false 'scoped run' }
	if ($InfrastructureError) { return & $verdict $false 'infrastructure failure' }
	if ($FailedCount -gt 0) { return & $verdict $false 'failing tests' }
	if ($ForeignLoadPercent -gt $MaxForeignLoadPercent) {
		return & $verdict $false ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, 'machine busy ({0:N1}% foreign CPU)', $ForeignLoadPercent))
	}
	return & $verdict $true 'recorded'
}
