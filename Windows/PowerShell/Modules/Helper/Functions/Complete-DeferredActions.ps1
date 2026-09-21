function Complete-DeferredActions {
	<#
	.SYNOPSIS
		Runs every tail Register-DeferredAction queued, in order, and empties the queue.

	.DESCRIPTION
		The drain half of the deferral seam. The flow calls it at the point where deferred work
		must have landed - Open-Workspace immediately before the Set-WorkspaceWindowLayout action,
		because the layout holds a window stable only while its title and dimensions stop changing
		and a deferred tail may retitle a window, and again when an action list ends without a
		layout action, so a tail never outlives the open that queued it.

		The queue is taken and cleared BEFORE the first tail runs: a tail that throws must not
		strand the ones behind it, nor leave itself behind for the next open to run against a
		workspace that is no longer the one being opened. Each tail runs in its own try/catch; a
		throw is reported as a warning under the tail's label and the next tail still runs. A no-op
		when nothing is queued, so every caller can call it unconditionally.

	.OUTPUTS
		[int] How many tails ran, whether or not they threw. 0 when the queue was empty.

	.EXAMPLE
		$null = Complete-DeferredActions
		Runs whatever the launch actions handed back; does nothing when they handed back nothing.
	#>
	[CmdletBinding()]
	[OutputType([int])]
	param ()

	if ($null -eq $script:DeferredActions -or $script:DeferredActions.Count -eq 0) { return 0 }

	# Taken and cleared first: neither a throw below nor a tail that registers another tail may
	# touch the list being walked, and nothing may survive into the next flow.
	$queued = @($script:DeferredActions)
	$script:DeferredActions.Clear()

	$ran = 0
	foreach ($entry in $queued) {
		$ran++
		Write-LogDebug " [Complete-DeferredActions] Running [$($entry.Label)] ($ran of $($queued.Count))"
		try {
			$splat = if ($entry.Parameters) { $entry.Parameters } else { @{} }
			$null = & $entry.Action @splat
		}
		catch {
			Write-LogWarning "Deferred action [$($entry.Label)] failed => $($_.Exception.Message)"
		}
	}

	return $ran
}
