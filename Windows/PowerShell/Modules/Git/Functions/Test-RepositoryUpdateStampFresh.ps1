function Test-RepositoryUpdateStampFresh {
	<#
	.SYNOPSIS
		Tells whether the startup repository update ran recently enough to skip it.

	.DESCRIPTION
		The throttle check of Invoke-StartupRepositoryUpdate. A missing stamp is never fresh, so a
		first run, or a run after the stamp was deleted, always goes ahead. Otherwise it depends on
		-Schedule:

		- Daily: fresh when the stamp was written since the current day began - today at
		  -DayStartHour:00, or yesterday at that hour while it is still earlier than that
		  (Get-RepositoryUpdateDayStart). So the update runs once per day, at the first chance
		  after the day starts, however late the previous run was.
		- Interval: fresh when the stamp was written less than -IntervalHours ago. An interval of 0
		  or less is never fresh, so the update runs in every shell.

		Invoke-StartupRepositoryUpdate asks twice: once before claiming the run (the cheap exit
		for every shell after the first), and once more after the claim, because another shell
		may have finished a run in between.

	.PARAMETER StampFile
		Full path of the stamp file (Logs\.last-repository-update).

	.PARAMETER Schedule
		Daily (default) or Interval.

	.PARAMETER DayStartHour
		The hour (0-23) a new day starts, for the Daily schedule. Default 6.

	.PARAMETER IntervalHours
		Minimum hours between two runs, for the Interval schedule. Default 24.

	.OUTPUTS
		[bool] - $true when the last run is recent enough to skip this one.

	.EXAMPLE
		Test-RepositoryUpdateStampFresh -StampFile (Join-Path $global:LoggingState.LogsDir ".last-repository-update") -DayStartHour 6
		$true when the startup update already ran since 06:00 today (or since 06:00 yesterday, before 06:00).

	.EXAMPLE
		Test-RepositoryUpdateStampFresh -StampFile (Join-Path $global:LoggingState.LogsDir ".last-repository-update") -Schedule Interval -IntervalHours 24
		$true when the startup update ran within the last 24 hours.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$StampFile,

		[Parameter(Mandatory = $false)]
		[ValidateSet('Daily', 'Interval')]
		[string]$Schedule = 'Daily',

		[Parameter(Mandatory = $false)]
		[ValidateRange(0, 23)]
		[int]$DayStartHour = 6,

		[Parameter(Mandatory = $false)]
		[double]$IntervalHours = 24
	)

	if (-not (Test-Path -LiteralPath $StampFile)) { return $false }

	$written = (Get-Item -LiteralPath $StampFile -Force).LastWriteTime

	if ($Schedule -eq 'Interval') {
		return ((Get-Date) - $written).TotalHours -lt $IntervalHours
	}

	return $written -ge (Get-RepositoryUpdateDayStart -DayStartHour $DayStartHour)
}
