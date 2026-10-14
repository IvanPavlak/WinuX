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
		it unconditionally after printing.

	.OUTPUTS
		[bool] - $true when the prompt was drawn again, $false when PSReadLine is not loaded or
		the redraw failed.

	.EXAMPLE
		Write-LogWarning "Something printed under the prompt"; $null = Restore-ShellPrompt
		Reports, then puts the prompt back under the report.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param()

	$readLine = 'Microsoft.PowerShell.PSConsoleReadLine' -as [type]
	if (-not $readLine) {
		return $false
	}

	try {
		[Console]::Write("`r")
		$readLine::InvokePrompt($null, [Console]::CursorTop)
		return $true
	}
	catch {
		return $false
	}
}
