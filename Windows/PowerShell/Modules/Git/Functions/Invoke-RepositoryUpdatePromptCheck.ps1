function Invoke-RepositoryUpdatePromptCheck {
	<#
	.SYNOPSIS
		The prompt installed by Register-RepositoryUpdatePromptCheck: the original prompt, plus the daily update once a day.

	.DESCRIPTION
		Runs the original prompt function first and keeps its text. That call is the first
		statement on purpose: a prompt reads the last command's success from `$?`, and any
		statement before it would reset that (the Oh My Posh error indicator would never show).

		Then, once the next day boundary in $global:WinuXRepositoryUpdatePrompt has passed, runs
		Invoke-StartupRepositoryUpdate - which checks the stamp and the lock itself, so a shell
		that loses the race to another one prints nothing - and moves the boundary to the next
		day. `$LASTEXITCODE` is put back afterwards, so the git calls of the update never show up
		as the exit code of the user's last command. The update prints its summary before the
		prompt text is returned, so the prompt is drawn below it.

		Never throws: a failure is swallowed and the prompt text is still returned. Without the
		recorded original prompt it returns PowerShell's default prompt text.

	.OUTPUTS
		[string] - the prompt text.

	.EXAMPLE
		Invoke-RepositoryUpdatePromptCheck
		The prompt text of the original prompt; the first call after the day starts also updates the repositories.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param()

	try { $promptText = & $global:WinuXRepositoryUpdatePrompt.Original }
	catch { $promptText = "PS $($ExecutionContext.SessionState.Path.CurrentLocation)$('>' * ($NestedPromptLevel + 1)) " }

	try {
		$state = $global:WinuXRepositoryUpdatePrompt
		if ($state -and (Get-Date) -ge $state.NextCheck) {
			$exitCode = $global:LASTEXITCODE
			try {
				Invoke-StartupRepositoryUpdate
			}
			finally {
				$global:LASTEXITCODE = $exitCode
				$state.NextCheck = (Get-RepositoryUpdateDayStart -DayStartHour $state.DayStartHour).AddDays(1)
			}
		}
	}
	catch { }

	return $promptText
}
