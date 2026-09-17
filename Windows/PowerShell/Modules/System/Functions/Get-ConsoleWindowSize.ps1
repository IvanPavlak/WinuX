function Get-ConsoleWindowSize {
	<#
	.SYNOPSIS
		Reads the console window size in character cells.

	.DESCRIPTION
		Returns an object with Width and Height taken from [Console]::WindowWidth and
		[Console]::WindowHeight - the number of columns and rows the terminal window shows
		at its current font size, which is the unit a text panel has to be judged against.

		Throws in hosts that have no console window (automation, some IDE hosts), which is
		exactly the signal Invoke-Fastfetch uses to skip its font auto-fit. The read
		is deliberately not wrapped: a caller that wants to degrade gracefully catches, one
		that wants the raw failure sees it.

		Exists as a function rather than an inline property read so callers that react to
		the window changing - Wait-ConsoleReflow polls it after every font keystroke - can be
		driven by a scripted sequence of sizes in tests.

	.OUTPUTS
		[pscustomobject] with Width and Height, both [int], in cells.

	.EXAMPLE
		Get-ConsoleWindowSize
		Returns something like Width=120, Height=30.

	.EXAMPLE
		$window = Get-ConsoleWindowSize
		if ($panelWidth -gt $window.Width) { "too wide" }
		Compares a measured panel against the live window.
	#>
	[CmdletBinding()]
	[OutputType([psobject])]
	param()

	return [pscustomobject]@{
		Width  = [Console]::WindowWidth
		Height = [Console]::WindowHeight
	}
}
