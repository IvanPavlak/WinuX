function Invoke-RerunLastCommandExit {
	<#
	.SYNOPSIS
		Executes the rerun exit seam.

	.DESCRIPTION
		Invokes the script-scoped exit action used by `ReRun-LastCommand` once the fresh
		shell has been opened and the original window has been closed. When no test seam is
		configured, exits the current process with code `0`.

		`ReRun-LastCommand` releases stuck modifier keys immediately before calling this,
		because `[Environment]::Exit` skips every finally block in the process - the same
		arrangement `Invoke-TerminateWindowsTerminalTabsExit` uses for its own exit.

	.EXAMPLE
		Invoke-RerunLastCommandExit
		Runs the configured exit seam or exits the current process cleanly.
	#>
	[CmdletBinding()]
	param()

	if ($script:RerunLastCommandExitAction) {
		& $script:RerunLastCommandExitAction
	}
	else {
		[Environment]::Exit(0)
	}
}
