function Get-RepositoryUpdateStartupSettings {
	<#
	.SYNOPSIS
		Reads RepositoryUpdate.Startup with every default filled in.

	.DESCRIPTION
		The one place that knows the automatic repository update's keys and their defaults, so
		Invoke-StartupRepositoryUpdate (whether a run is due) and Register-RepositoryUpdatePromptCheck
		(whether open shells watch for a new day) can never disagree.

		- Enabled: `RepositoryUpdate.Startup.Enabled`, default $false.
		- Schedule: `RepositoryUpdate.Startup.Schedule`, "Daily" (default) or "Interval". Anything
		  else falls back to "Daily".
		- DayStartHour: `RepositoryUpdate.Startup.DayStartHour`, the hour (0-23) a new day starts for
		  the Daily schedule, default 6. Out of range or not a number falls back to 6.
		- IntervalHours: `RepositoryUpdate.Startup.IntervalHours`, the minimum hours between runs for
		  the Interval schedule, default 24. Not a number falls back to 24.

	.OUTPUTS
		[pscustomobject] with Enabled, Schedule, DayStartHour and IntervalHours.

	.EXAMPLE
		Get-RepositoryUpdateStartupSettings
		Enabled Schedule DayStartHour IntervalHours
		------- -------- ------------ -------------
		   True Daily               6            24
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param()

	$startup = Get-ConfigSetting -Path 'RepositoryUpdate.Startup'

	$enabled = $false
	$schedule = 'Daily'
	$dayStartHour = 6
	$intervalHours = 24.0

	if ($startup) {
		if ($null -ne $startup.Enabled) { $enabled = [bool]$startup.Enabled }

		# -eq matches case-insensitively; anything but "Interval" is the Daily schedule.
		if ("$($startup.Schedule)" -eq 'Interval') { $schedule = 'Interval' }

		$hour = 0
		if ($null -ne $startup.DayStartHour -and [int]::TryParse("$($startup.DayStartHour)", [ref]$hour) -and $hour -ge 0 -and $hour -le 23) {
			$dayStartHour = $hour
		}

		$hours = 0.0
		if ($null -ne $startup.IntervalHours -and [double]::TryParse("$($startup.IntervalHours)", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$hours)) {
			$intervalHours = $hours
		}
	}

	return [pscustomobject]@{
		Enabled       = $enabled
		Schedule      = $schedule
		DayStartHour  = $dayStartHour
		IntervalHours = $intervalHours
	}
}
