function Invoke-TerminateWindowsTerminalTabsExit {
	<#
	.SYNOPSIS
		Executes the terminal-tab exit seam.

	.DESCRIPTION
		Invokes the script-scoped exit action used by `Terminate-WindowsTerminalTabs`
		during `-IncludeCurrent` cleanup. When no test seam is configured, exits the
		current process with code `0`.

	.EXAMPLE
		Invoke-TerminateWindowsTerminalTabsExit
		Runs the configured exit seam or exits the current process cleanly.
	#>
	[CmdletBinding()]
	param()

	if ($script:TerminateWindowsTerminalTabsExitAction) {
		& $script:TerminateWindowsTerminalTabsExitAction
	}
	else {
		[Environment]::Exit(0)
	}
}
