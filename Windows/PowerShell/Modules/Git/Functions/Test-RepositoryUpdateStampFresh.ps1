function Test-RepositoryUpdateStampFresh {
	<#
	.SYNOPSIS
		Tells whether the startup repository update ran recently enough to skip it.

	.DESCRIPTION
		The throttle check of Invoke-StartupRepositoryUpdate: returns $true when the stamp file
		exists and was written less than -IntervalHours ago. A missing stamp is never fresh, so
		a first run, or a run after the stamp was deleted, always goes ahead. An interval of 0
		or less is never fresh either, so the update runs in every shell.

		Invoke-StartupRepositoryUpdate asks twice: once before claiming the run (the cheap exit
		for every shell after the first), and once more after the claim, because another shell
		may have finished a run in between.

	.PARAMETER StampFile
		Full path of the stamp file (Logs\.last-repository-update).

	.PARAMETER IntervalHours
		Minimum hours between two runs.

	.OUTPUTS
		[bool] - $true when the last run is younger than the interval.

	.EXAMPLE
		Test-RepositoryUpdateStampFresh -StampFile (Join-Path $global:LoggingState.LogsDir ".last-repository-update") -IntervalHours 24
		$true when the startup update ran within the last 24 hours.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$StampFile,

		[Parameter(Mandatory = $true)]
		[double]$IntervalHours
	)

	if (-not (Test-Path -LiteralPath $StampFile)) { return $false }

	$stampAge = (Get-Date) - (Get-Item -LiteralPath $StampFile -Force).LastWriteTime
	return ($stampAge.TotalHours -lt $IntervalHours)
}
