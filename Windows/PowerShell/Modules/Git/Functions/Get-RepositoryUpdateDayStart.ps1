function Get-RepositoryUpdateDayStart {
	<#
	.SYNOPSIS
		Returns when the current day began, for a day that starts at a given hour.

	.DESCRIPTION
		The day boundary of the Daily schedule of the automatic repository update: the most
		recent moment at -DayStartHour:00 local time that is not later than -At. Before that hour
		the day is still yesterday's, so work past midnight never counts as a new day.

		Add one day to the result for the next boundary, which is when
		Register-RepositoryUpdatePromptCheck has open shells look again.

	.PARAMETER DayStartHour
		The hour (0-23) a new day starts.

	.PARAMETER At
		The moment to place in its day. Defaults to now.

	.OUTPUTS
		[datetime] - the start of the day -At belongs to.

	.EXAMPLE
		Get-RepositoryUpdateDayStart -DayStartHour 6 -At ([datetime]'2026-10-08 05:30')
		Wednesday, 7 October 2026 06:00:00 - 05:30 still belongs to the day that began yesterday.
	#>
	[CmdletBinding()]
	[OutputType([datetime])]
	param(
		[Parameter(Mandatory = $true)]
		[ValidateRange(0, 23)]
		[int]$DayStartHour,

		[Parameter(Mandatory = $false)]
		[datetime]$At = (Get-Date)
	)

	$dayStart = $At.Date.AddHours($DayStartHour)
	if ($At -lt $dayStart) { $dayStart = $dayStart.AddDays(-1) }
	return $dayStart
}
