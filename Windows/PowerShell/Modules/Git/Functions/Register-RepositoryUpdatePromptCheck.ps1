function Register-RepositoryUpdatePromptCheck {
	<#
	.SYNOPSIS
		Deprecated. Makes an open shell run the daily repository update at its first prompt after the day starts - use Register-StartupTaskPromptCheck.

	.DESCRIPTION
		DEPRECATED since 2.12.0, removed in 3.0.0. The automatic repository update is a startup
		task now, and Register-StartupTaskPromptCheck does this for every startup task that runs
		once per day in a newly opened terminal; the profile calls that one. This function still
		works on its own and warns once per session.

		The Daily schedule of the automatic repository update runs once per day. A new shell
		covers it through Invoke-StartupRepositoryUpdate, but a shell that was already open when
		the day began - a terminal left open overnight, a machine woken from sleep - never starts
		again. This function makes such a shell look again at its next prompt.

		It wraps the current global `prompt` function (the Oh My Posh prompt, or whatever the
		profile defined) with Invoke-RepositoryUpdatePromptCheck and records the next day boundary
		(Get-RepositoryUpdateDayStart plus one day). Until that moment every prompt costs one time
		comparison; the first prompt after it runs Invoke-StartupRepositoryUpdate, which decides
		for real (stamp, lock), and moves the boundary to the next day.

		Does nothing unless `RepositoryUpdate.Startup.Enabled` is $true with the Daily schedule
		(Get-RepositoryUpdateStartupSettings) - the Interval schedule is only checked when a shell
		starts. Calling it again (Reload-PowerShellProfile) never wraps the prompt twice: an
		already wrapped prompt only gets its boundary refreshed, and a prompt the profile
		redefined is wrapped afresh.

		The profile no longer calls it. It reads only the deprecated `RepositoryUpdate.Startup`
		keys, so it does nothing for a RepositoryUpdate task written under `Startup.Tasks`.

	.OUTPUTS
		None. Sets $global:WinuXRepositoryUpdatePrompt (the original prompt, the day start hour
		and the next boundary) and replaces the global prompt function.

	.EXAMPLE
		Register-RepositoryUpdatePromptCheck
		From now on, the first prompt after the next day starts updates the repositories.
	#>
	[CmdletBinding()]
	param()

	if (-not ($global:WinuXDeprecationWarned -is [System.Collections.IDictionary])) { $global:WinuXDeprecationWarned = @{} }
	if (-not $global:WinuXDeprecationWarned['Register-RepositoryUpdatePromptCheck']) {
		$global:WinuXDeprecationWarned['Register-RepositoryUpdatePromptCheck'] = $true
		Write-LogWarning "Register-RepositoryUpdatePromptCheck is deprecated since 2.12.0 and removed in 3.0.0 - use Register-StartupTaskPromptCheck"
	}

	$settings = Get-RepositoryUpdateStartupSettings
	if (-not $settings.Enabled -or $settings.Schedule -ne 'Daily') { return }

	$current = ${function:global:prompt}
	if (-not $current) { return }

	$wrapperText = 'Invoke-RepositoryUpdatePromptCheck'
	$nextCheck = (Get-RepositoryUpdateDayStart -DayStartHour $settings.DayStartHour).AddDays(1)
	$state = $global:WinuXRepositoryUpdatePrompt

	if ($state -and $current.ToString().Trim() -eq $wrapperText) {
		$state.DayStartHour = $settings.DayStartHour
		$state.NextCheck = $nextCheck
		return
	}

	$global:WinuXRepositoryUpdatePrompt = [pscustomobject]@{
		Original     = $current
		DayStartHour = $settings.DayStartHour
		NextCheck    = $nextCheck
	}
	# Unbound, so the prompt resolves the command like any typed one, not inside this module.
	Set-Item -LiteralPath function:global:prompt -Value ([scriptblock]::Create($wrapperText))
}
