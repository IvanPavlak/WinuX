function Invoke-StartupTaskPromptCheck {
	<#
	.SYNOPSIS
		The prompt installed by Register-StartupTaskPromptCheck: the original prompt, plus the once-a-day startup tasks when a new day starts.

	.DESCRIPTION
		Runs the original prompt function first and keeps its text. That call is the first
		statement on purpose: a prompt reads the last command's success from `$?`, and any
		statement before it would reset that (the Oh My Posh error indicator would never show).

		Then, once the next day boundary in $global:WinuXStartupTaskPrompt has passed, runs
		`Invoke-StartupTasks -Trigger TerminalOpen` - each task checks its stamp and its lock
		itself, so a shell that loses the race to another one prints nothing - and has
		Register-StartupTaskPromptCheck move the boundary on. `$LASTEXITCODE` is put back
		afterwards, so nothing a task ran shows up as the exit code of the user's last command.
		The tasks print before the prompt text is returned, so the prompt is drawn below them.

		Never throws: a failure is swallowed and the prompt text is still returned. Without the
		recorded original prompt it returns PowerShell's default prompt text.

	.OUTPUTS
		[string] - the prompt text.

	.EXAMPLE
		Invoke-StartupTaskPromptCheck
		The prompt text of the original prompt; the first call after the day starts also runs the once-a-day startup tasks.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param()

	try { $promptText = & $global:WinuXStartupTaskPrompt.Original }
	catch { $promptText = "PS $($ExecutionContext.SessionState.Path.CurrentLocation)$('>' * ($NestedPromptLevel + 1)) " }

	try {
		$state = $global:WinuXStartupTaskPrompt
		if ($state -and (Get-Date) -ge $state.NextCheck) {
			$exitCode = $global:LASTEXITCODE
			# Moved on first, so a run that throws is not tried again at every prompt.
			$state.NextCheck = (Get-Date).AddDays(1)
			try {
				$null = Invoke-StartupTasks -Trigger TerminalOpen
			}
			finally {
				$global:LASTEXITCODE = $exitCode
				Register-StartupTaskPromptCheck
			}
		}
	}
	catch { }

	return $promptText
}
