function Register-StartupTaskPromptCheck {
	<#
	.SYNOPSIS
		Makes an open shell run its once-a-day startup tasks at its first prompt after the day starts.

	.DESCRIPTION
		A startup task with the TerminalOpen trigger and `Frequency = "OncePerDay"` runs in the
		first shell opened each day. A shell that was already open when the day began - a
		terminal left open overnight, a machine woken from sleep - never opens again. This
		function makes such a shell look again at its next prompt.

		It wraps the current global `prompt` function (the Oh My Posh prompt, or whatever the
		profile defined) with Invoke-StartupTaskPromptCheck and records the next day boundary:
		the earliest moment at which one of those tasks starts a new day (its DayStartHour, today
		or tomorrow). Until then every prompt costs one time comparison; the first prompt after
		it runs `Invoke-StartupTasks -Trigger TerminalOpen`, which decides for real (stamp, lock),
		and moves the boundary on.

		Does nothing when no valid, enabled task in this machine's scope has TerminalOpen with
		OncePerDay - every other frequency is only checked when a shell starts - and nothing in a
		shell that belongs to a startup task. Calling it again (Reload-PowerShellProfile) never
		wraps the prompt twice: an already wrapped prompt only gets its boundary refreshed, and a
		prompt the profile redefined is wrapped afresh.

		The profile calls it from the idle-time hook, right before
		`Invoke-StartupTasks -Trigger TerminalOpen`.

	.OUTPUTS
		None. Sets $global:WinuXStartupTaskPrompt (the original prompt and the next boundary) and
		replaces the global prompt function.

	.EXAMPLE
		Register-StartupTaskPromptCheck
		From now on, the first prompt after the next day starts runs the once-a-day tasks.
	#>
	[CmdletBinding()]
	param()

	if ($global:WinuXStartupTaskShell) { return }

	$daily = @(Get-StartupTaskDefinitions -Trigger TerminalOpen | Where-Object {
			$_.Valid -and $_.InScope -and $_.Parameters.Enabled -and $_.Parameters.Frequency -eq 'OncePerDay'
		})
	if ($daily.Count -eq 0) { return }

	$current = ${function:global:prompt}
	if (-not $current) { return }

	# The earliest next day start among the daily tasks.
	$now = Get-Date
	$nextCheck = $null
	foreach ($task in $daily) {
		$boundary = $now.Date.AddHours([int]$task.Parameters.DayStartHour)
		if ($boundary -le $now) { $boundary = $boundary.AddDays(1) }
		if ($null -eq $nextCheck -or $boundary -lt $nextCheck) { $nextCheck = $boundary }
	}

	$wrapperText = 'Invoke-StartupTaskPromptCheck'
	$state = $global:WinuXStartupTaskPrompt

	if ($current.ToString().Trim() -eq $wrapperText) {
		if ($state) {
			$state.NextCheck = $nextCheck
		}
		else {
			# The wrapper is installed but its state is gone, so the original prompt is unknown.
			# Recording the wrapper as its own original would make it call itself without end;
			# PowerShell's default prompt stands in instead.
			$global:WinuXStartupTaskPrompt = [pscustomobject]@{
				Original  = { "PS $($ExecutionContext.SessionState.Path.CurrentLocation)$('>' * ($NestedPromptLevel + 1)) " }
				NextCheck = $nextCheck
			}
		}
		return
	}

	$global:WinuXStartupTaskPrompt = [pscustomobject]@{
		Original  = $current
		NextCheck = $nextCheck
	}
	# Unbound, so the prompt resolves the command like any typed one, not inside this module.
	Set-Item -LiteralPath function:global:prompt -Value ([scriptblock]::Create($wrapperText))
}
