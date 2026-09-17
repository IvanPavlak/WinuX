function Wait-ConsoleReflow {
	<#
	.SYNOPSIS
		Waits for the console window size to change, returning the new size.

	.DESCRIPTION
		After a font-size keystroke Windows Terminal reflows asynchronously, so the window
		size read immediately afterwards is often still the old one. This polls
		Get-ConsoleWindowSize every -PollIntervalMilliseconds until it differs from -Before,
		or until -TimeoutMilliseconds passes, and returns the last size read.

		A timeout is not an error: it is how a keystroke that changed nothing reports itself -
		Ctrl+0 when the font is already at the default, Ctrl+Minus when the terminal is at its
		minimum font. The returned size then equals -Before, and the caller compares the two to
		tell "reflowed" from "nothing happened".

		Replaces the fixed sleep Invoke-Fastfetch used to take after each keystroke: a
		fixed wait is either too long on a fast machine or too short on a slow one, where the
		pre-reflow size was read and the fit misjudged. Polling returns the moment the terminal
		has moved.

	.PARAMETER Before
		The window size read before the keystroke, as returned by Get-ConsoleWindowSize
		(an object with Width and Height).

	.PARAMETER TimeoutMilliseconds
		How long to keep polling before giving up and returning the unchanged size.

	.PARAMETER PollIntervalMilliseconds
		Pause between two reads. Default 10.

	.OUTPUTS
		[pscustomobject] with Width and Height - the changed size, or -Before's values when
		nothing changed within the timeout.

	.EXAMPLE
		$before = Get-ConsoleWindowSize
		Send-TerminalFontKey -Action Decrease
		$after = Wait-ConsoleReflow -Before $before -TimeoutMilliseconds 10
		Shrinks the font and returns as soon as the window has reflowed.

	.EXAMPLE
		if ($after.Width -eq $before.Width -and $after.Height -eq $before.Height) { "no reflow" }
		Detects a keystroke that changed nothing.
	#>
	[CmdletBinding()]
	[OutputType([psobject])]
	param(
		[Parameter(Mandatory)]
		[psobject]$Before,

		[Parameter(Mandatory)]
		[ValidateRange(1, 10000)]
		[int]$TimeoutMilliseconds,

		[ValidateRange(1, 1000)]
		[int]$PollIntervalMilliseconds = 10
	)

	$timer = [Diagnostics.Stopwatch]::StartNew()
	$current = Get-ConsoleWindowSize

	while (($current.Width -eq $Before.Width -and $current.Height -eq $Before.Height) -and
		$timer.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
		Start-Sleep -Milliseconds $PollIntervalMilliseconds
		$current = Get-ConsoleWindowSize
	}

	if ($current.Width -ne $Before.Width -or $current.Height -ne $Before.Height) {
		Write-LogDebug "[Wait-ConsoleReflow] window $($Before.Width)x$($Before.Height) => $($current.Width)x$($current.Height) after $($timer.ElapsedMilliseconds)ms"
	}
	else {
		Write-LogDebug "[Wait-ConsoleReflow] window still $($Before.Width)x$($Before.Height) after ${TimeoutMilliseconds}ms - no reflow"
	}

	return $current
}
