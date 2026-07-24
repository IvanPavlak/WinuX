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
		# [Environment]::Exit skips every finally block in the process, so callers' cleanup
		# (notably the keyboard-modifier self-heal in Open-Workspace's finally) never runs.
		# Stuck-modifier state is OS-global and survives the process - release it here as the
		# last act before exiting.
		if (Get-Command Reset-KeyboardModifiers -ErrorAction SilentlyContinue) {
			$null = Reset-KeyboardModifiers
		}
		[Environment]::Exit(0)
	}
}
