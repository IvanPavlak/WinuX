function Restore-ShellPrompt {
	<#
	.SYNOPSIS
		Draws the prompt again after something printed below it while PSReadLine was already
		waiting for input.

	.DESCRIPTION
		Work that runs once the shell is at its prompt - the deferred startup queue the profile
		runs from its one PowerShell.OnIdle event, or anything else that prints from an event
		action - pushes the prompt up the screen, and PSReadLine keeps waiting on a blank line
		with no prompt visible. This writes a carriage return (output written during ReadLine
		leaves the cursor past column 0) and asks PSReadLine to draw the prompt at the current
		console row through InvokePrompt.

		Nothing happens outside PSReadLine - the type is not loaded in a plain host or in a test
		runner - and a redraw that fails is swallowed: the function never throws, so a caller runs
		it unconditionally after printing. The profile dot-sources this file before the first
		prompt, so the redraw never autoloads the Helper module.

	.PARAMETER ReadLine
		The line editor type whose static InvokePrompt draws the prompt. Defaults to PSReadLine's
		Microsoft.PowerShell.PSConsoleReadLine when it is loaded, and to $null - nothing to redraw
		- when it is not. A parameter so tests can pass a stand-in type instead of driving the
		real console.

	.OUTPUTS
		[bool] - $true when the prompt was drawn again, $false when there is no line editor or
		the redraw failed.

	.EXAMPLE
		Write-LogWarning "Something printed under the prompt"; $null = Restore-ShellPrompt
		Reports, then puts the prompt back under the report.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter()]
		[AllowNull()]
		[type]$ReadLine = ('Microsoft.PowerShell.PSConsoleReadLine' -as [type])
	)

	if (-not $ReadLine) {
		return $false
	}

	try {
		$row = [Console]::CursorTop
		[Console]::Write("`r")
		$ReadLine::InvokePrompt($null, $row)
		return $true
	}
	catch {
		return $false
	}
}
