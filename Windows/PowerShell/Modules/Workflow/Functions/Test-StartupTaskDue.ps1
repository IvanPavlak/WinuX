function Test-StartupTaskDue {
	<#
	.SYNOPSIS
		Tells whether a startup task should run now, given its frequency and its stamp file.

	.DESCRIPTION
		The frequency check of Invoke-StartupTask. A task writes its stamp file only after a run
		that succeeded, so a run that failed, was skipped for a condition or never finished is
		due again at the next trigger. A missing stamp is always due.

		- EveryTime (default): always due. The stamp is not read.
		- OncePerBoot: due when the stamp is older than -BootTime. With Windows Fast Startup a
		  shutdown is a hibernation, so the boot time only moves on a restart.
		- OncePerDay: due when the stamp is older than the start of the current day - today at
		  -DayStartHour:00, or yesterday at that hour while it is still earlier than that. Work
		  past midnight therefore never counts as a new day.
		- Interval: due when the stamp is at least -IntervalHours old. An interval of 0 or less
		  is always due.

	.PARAMETER StampFile
		Full path of the task's stamp file (Logs\.startup-task-<Name>.stamp).

	.PARAMETER Frequency
		EveryTime (default), OncePerBoot, OncePerDay or Interval.

	.PARAMETER DayStartHour
		The hour (0-23) a new day starts, for OncePerDay. Default 6.

	.PARAMETER IntervalHours
		Minimum hours between two successful runs, for Interval. Default 24.

	.PARAMETER Now
		The moment to decide for. Defaults to the current time; a parameter so tests need no clock.

	.PARAMETER BootTime
		When the machine started, for OncePerBoot. Defaults to the current time minus the
		system's uptime.

	.OUTPUTS
		[bool] - $true when the task should run.

	.EXAMPLE
		Test-StartupTaskDue -StampFile (Join-Path (Get-LogPath -Directory) ".startup-task-MyTask.stamp") -Frequency OncePerDay
		$false when MyTask already succeeded since 06:00 today (or since 06:00 yesterday, before 06:00).

	.EXAMPLE
		Test-StartupTaskDue -StampFile $stamp -Frequency Interval -IntervalHours 4
		$true when the last successful run is four hours old or older.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$StampFile,

		[Parameter()]
		[ValidateSet('EveryTime', 'OncePerBoot', 'OncePerDay', 'Interval')]
		[string]$Frequency = 'EveryTime',

		[Parameter()]
		[ValidateRange(0, 23)]
		[int]$DayStartHour = 6,

		[Parameter()]
		[double]$IntervalHours = 24,

		[Parameter()]
		[datetime]$Now = (Get-Date),

		[Parameter()]
		[datetime]$BootTime = (Get-Date).AddMilliseconds(-[Environment]::TickCount64)
	)

	if ($Frequency -eq 'EveryTime') { return $true }
	if (-not (Test-Path -LiteralPath $StampFile)) { return $true }

	$written = (Get-Item -LiteralPath $StampFile -Force).LastWriteTime

	if ($Frequency -eq 'OncePerBoot') {
		return $written -lt $BootTime
	}

	if ($Frequency -eq 'Interval') {
		return ($Now - $written).TotalHours -ge $IntervalHours
	}

	$dayStart = $Now.Date.AddHours($DayStartHour)
	if ($Now -lt $dayStart) { $dayStart = $dayStart.AddDays(-1) }
	return $written -lt $dayStart
}
