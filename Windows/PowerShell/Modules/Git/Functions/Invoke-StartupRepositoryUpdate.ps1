function Invoke-StartupRepositoryUpdate {
	<#
	.SYNOPSIS
		Deprecated. Runs the startup task RepositoryUpdate - use Invoke-StartupTask RepositoryUpdate.

	.DESCRIPTION
		DEPRECATED since 2.12.0, removed in 3.0.0. The automatic repository update is a startup
		task now (`Startup.Tasks`, run by Invoke-StartupTasks), and this function only forwards
		to it. It warns once per session.

		It runs the startup task named RepositoryUpdate in the current shell, through
		Invoke-StartupTask, with a condition tested once instead of waited for. That task is
		either the one the configuration defines under that name, or - while the deprecated
		`RepositoryUpdate.Startup.Enabled` is $true and no task has the name - the one
		Get-StartupTaskDefinitions builds from the `RepositoryUpdate.Startup` keys:
		`Update-Repositories -All -NoClone -Quiet` (or `-Group` with the groups of
		`RepositoryUpdate.Startup.Scope`), once per day or per interval.

		Two things differ from the function this replaces. The stamp is the startup task's
		(Logs\.startup-task-RepositoryUpdate.stamp) and is written only after a run that
		succeeded, so a run that threw is tried again at the next chance. And the lock is the
		startup task's (Logs\.startup-task-RepositoryUpdate.lock).

		Migration: call `Invoke-StartupTasks -Trigger TerminalOpen` (what the profile does), or
		`Invoke-StartupTask RepositoryUpdate -Force` to run it now.

		Never throws: an error is logged and the shell carries on. The one thing it cannot
		contain is a configured RepositoryUpdate task whose command asks for Administrator
		privileges: Test-AdminPrivileges stops the pipeline, and the caller with it (see
		Invoke-StartupTask). The command built from the deprecated keys never asks.

	.PARAMETER Force
		Run now, ignoring whether the task is enabled and whether it is due. With the deprecated
		keys this also runs when `RepositoryUpdate.Startup.Enabled` is not $true.

	.PARAMETER RedrawPrompt
		After a run, draw the prompt again below its output (Restore-ShellPrompt). Nothing
		happens when no update ran.

	.EXAMPLE
		Invoke-StartupRepositoryUpdate
		Updates the repositories if the RepositoryUpdate startup task is due.

	.EXAMPLE
		Invoke-StartupRepositoryUpdate -Force
		Runs the RepositoryUpdate startup task right now.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$Force,

		[Parameter(Mandatory = $false)]
		[switch]$RedrawPrompt
	)

	if (-not ($global:WinuXDeprecationWarned -is [System.Collections.IDictionary])) { $global:WinuXDeprecationWarned = @{} }
	if (-not $global:WinuXDeprecationWarned['Invoke-StartupRepositoryUpdate']) {
		$global:WinuXDeprecationWarned['Invoke-StartupRepositoryUpdate'] = $true
		Write-LogWarning "Invoke-StartupRepositoryUpdate is deprecated since 2.12.0 and removed in 3.0.0 - use Invoke-StartupTask RepositoryUpdate, or Invoke-StartupTasks -Trigger TerminalOpen"
	}

	$result = $null
	try {
		$definition = @(Get-StartupTaskDefinitions -Name RepositoryUpdate -IncludeLegacyDisabled:$Force) | Select-Object -First 1
		if (-not $definition -or -not $definition.Valid) { return }

		$arguments = @{}
		foreach ($key in @($definition.Parameters.Keys)) { $arguments[$key] = $definition.Parameters[$key] }
		$arguments.Remove('Parallel')
		$arguments.Remove('KeepOpen')
		$arguments.Window = 'Current'
		$arguments.Trigger = 'TerminalOpen'
		$arguments.NoConditionWait = $true
		$arguments.Force = [bool]$Force

		$result = Invoke-StartupTask @arguments
	}
	catch {
		Write-LogError "Startup repository update failed: $_"
	}

	# Only after an update was attempted - a disabled, not due or already running task prints
	# nothing, so there is no prompt to restore.
	if ($RedrawPrompt -and $result -and $result.Status -in 'Succeeded', 'Failed') {
		$null = Restore-ShellPrompt
	}
}
