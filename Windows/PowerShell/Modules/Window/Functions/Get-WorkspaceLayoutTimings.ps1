function Get-WorkspaceLayoutTimings {
	<#
	.SYNOPSIS
		Returns the phase timings recorded by the most recent Set-WorkspaceWindowLayout run in this session.

	.DESCRIPTION
		Set-WorkspaceWindowLayout keeps a phase clock while it runs and publishes the result when it
		finishes - on success, on an early return and on the error path alike. This getter is the
		read side of that record. It exists so a caller in another module (Open-Workspace, which
		owns the workspace benchmark and writes the row through Write-WorkspaceBenchmark) can pick
		the timings up without reaching into the Window module's private state.

		The record describes ONE run: the workspace it applied, the layout file, the attempt count,
		how the run ended and, per phase, the seconds spent. Phases accumulate across the in-process
		retry loop, so a run that positioned and snapped twice reports the sum for Position and Snap
		rather than the last attempt only. Phases that did not occur are simply absent.

		Phases, in execution order: Preamble (RPC probe, layout file, validation, snapshot read),
		Desktops (virtual desktop resize), FancyZones (zone layouts applied per desktop), Wait
		(Wait-ForWorkspaceWindows), Normalize (browser first-tab and first-open resize passes),
		Position (Set-WindowLayouts and the pre-snap resize), Snap (Snap-AllWindows), Verify
		(Confirm-WorkspaceWindowPositions), Retry (the FancyZones reset between in-process attempts),
		Save (snapshot write, empty-desktop cleanup, visualization) and Other (whatever ran after
		the last mark - an early return, the escalation bookkeeping, the catch block).

		Returns $null when no layout has run in this session. The value is replaced by every run,
		so a caller comparing it against its own clock should check RecordedAt.

	.OUTPUTS
		[pscustomobject] with Workspace, LayoutFile, Alongside, DesktopOffset, Attempts, Outcome
		(Applied, Escalated, Error or Aborted), TotalSeconds, Phases (ordered phase => seconds) and
		RecordedAt; or $null.

	.EXAMPLE
		Set-WorkspaceWindowLayout -WorkspaceName MyWorkspace
		(Get-WorkspaceLayoutTimings).Phases
		# Preamble 0.5, Desktops 0.1, FancyZones 3.8, Wait 15.1, ...

	.EXAMPLE
		$timings = Get-WorkspaceLayoutTimings
		if ($timings -and $timings.Attempts -gt 1) { "the last layout needed $($timings.Attempts) attempts" }
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param ()

	return $script:LastWorkspaceLayoutTimings
}
