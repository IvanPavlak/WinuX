function Set-WorkspaceRerunCommand {
	<#
	.SYNOPSIS
		Records (or clears) the exact Open-Workspace invocation of the open in progress, for the failure-path respawn.

	.DESCRIPTION
		Open-Workspace resolves its workspace names (the user may have picked them from the
		interactive menu) and records the exact invocation here, so that when
		Set-WorkspaceWindowLayout exhausts its in-process retries and escalates to
		ReRun-LastCommand, the fresh shell reruns precisely this command instead of scraping the
		shared PSReadLine history, where any other session may have written a newer line.

		The record is module state, deliberately not an environment variable. A process
		environment variable is inherited by every application and terminal tab the open
		spawns - Windows Terminal hands the wt.exe caller's environment to command-line-created
		panes - so a standalone Set-WorkspaceWindowLayout escalation typed later into a project
		tab would have respawned the whole inherited workspace open. Module state lives and dies
		with this process only. Open-Workspace clears it when the open ends (its finally block,
		and before a terminating action exits the process).

	.PARAMETER Command
		The command line to record. An empty or whitespace value clears the record.

	.PARAMETER Clear
		Clears the record. Equivalent to an empty -Command.

	.EXAMPLE
		Set-WorkspaceRerunCommand -Command "Open-Workspace -Workspace 'WinuX'"

	.EXAMPLE
		Set-WorkspaceRerunCommand -Clear
	#>
	[CmdletBinding()]
	param(
		[Parameter(Position = 0)]
		[AllowNull()]
		[AllowEmptyString()]
		[string]$Command,

		[Parameter()]
		[switch]$Clear
	)

	if ($Clear -or [string]::IsNullOrWhiteSpace($Command)) {
		$script:WorkspaceRerunCommand = $null
		return
	}

	$script:WorkspaceRerunCommand = $Command
}
