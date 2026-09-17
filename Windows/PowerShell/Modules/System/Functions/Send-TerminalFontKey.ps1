function Send-TerminalFontKey {
	<#
	.SYNOPSIS
		Sends one of Windows Terminal's font-size keystrokes to the active window.

	.DESCRIPTION
		Reset sends Ctrl+0 ("reset font size"), Decrease sends Ctrl+Minus ("decrease font
		size") - both Windows Terminal default bindings - through SendKeys, so they land in
		whatever window has focus, which for a shell that is running this function is its own
		terminal tab.

		Windows Terminal exposes no API for the font size of a running session; the key
		bindings are the only way to change it from inside the shell, which is why
		Invoke-Fastfetch's auto-fit is built on them. The function does not check
		that the bindings exist - a custom `actions` list can drop them - because it cannot:
		the caller detects a keystroke that changed nothing by reading the window size
		before and after (see Wait-ConsoleReflow).

		Honours -WhatIf: the mapping is logged and nothing is sent. That is also how the
		function is tested without a keystroke ever leaving the test process, and
		Invoke-Fastfetch's own suite mocks it outright.

	.PARAMETER Action
		Reset (Ctrl+0) or Decrease (Ctrl+Minus).

	.EXAMPLE
		Send-TerminalFontKey -Action Reset
		Returns the font to the profile default.

	.EXAMPLE
		Send-TerminalFontKey -Action Decrease
		Shrinks the font one step.

	.EXAMPLE
		Send-TerminalFontKey -Action Decrease -WhatIf
		Reports what would be sent without sending it.
	#>
	[CmdletBinding(SupportsShouldProcess)]
	param(
		[Parameter(Mandatory)]
		[ValidateSet("Reset", "Decrease")]
		[string]$Action
	)

	$keys = if ($Action -eq "Reset") { "^0" } else { "^-" }
	Write-LogDebug "[Send-TerminalFontKey] $Action => SendKeys [$keys]"

	if (-not $PSCmdlet.ShouldProcess("active terminal window", "Send $Action keystroke [$keys]")) {
		return
	}

	Add-WindowsFormsType -Quiet
	[System.Windows.Forms.SendKeys]::SendWait($keys)
}
