function Invoke-ReadyDesktopPass {
	<#
	.SYNOPSIS
		Positions, resizes and snaps one virtual desktop as soon as the wait reports every entry on it stable.

	.DESCRIPTION
		The OnDesktopReady callback of Wait-ForWorkspaceWindows, as a named function. The wait
		ends when the SLOWEST window of the whole workspace has been stable for a second; every
		other window has been sitting stable for seconds by then, and the whole position and snap
		cost used to be paid after that. Wait-ForWorkspaceWindows reports each desktop whose
		entries are all stable while others still load, and this pass positions, resizes and
		snaps that desktop right away:

		  - the WHOLE layout is handed to Set-WindowLayouts so duplicate keys are counted across
		    desktops, only that desktop's entries processed (-DesktopNumbers);
		  - claims are restricted to the windows the wait has confirmed stable ANYWHERE so far
		    (Claims.WithCandidates: a window still loading is never claimed). The wait matches an
		    entry by process OR title, so its window for a titled browser entry is often a
		    different window of that browser; a per-entry whitelist filtered out the very window
		    the layout pass finds by title and left the entry unplaced (the 2026-09-03
		    regression). What the whitelist has to guarantee is only that a window still loading
		    is never claimed;
		  - results are appended to the one tracking set the whole open shares
		    (-KeepPositionedWindows) and the desktop is snapped alone.

		Only what was actually placed counts as done: a Configured row goes into the pipeline's
		PipelinedResults, PipelinedEntryKeys and Claims.Excluded; a Not Found row is dropped so
		the pass after the wait places that entry, exactly as before pipelining, and the
		shortfall tally is not counted twice. Any failure leaves the tallies untouched and the
		tail positions the desktop with the others. The phase clock books this pass's own time
		under Position and Snap, not Wait, and a running spinner is paused around it.

	.PARAMETER Pipeline
		The layout pipeline state (New-WorkspaceLayoutPipelineState).

	.PARAMETER ReadyDesktopNumber
		The layout's 1-based desktop number the wait reported ready.

	.PARAMETER ReadyEntries
		Array of @{ LayoutEntry; Window } for the desktop's stable entries.

	.PARAMETER StableWindowHandles
		Handles of EVERY window stable in the wait's poll, any entry, any desktop.

	.PARAMETER AbandonedEntries
		Layout entries the wait has abandoned so far; the layout pass gives them one search
		instead of the 1.5 s not-found ladder, which inside the wait would delay the other
		desktops.

	.OUTPUTS
		None.

	.EXAMPLE
		$onDesktopReady = { param($d, $e, $h, $a) Invoke-ReadyDesktopPass -Pipeline $pipeline -ReadyDesktopNumber $d -ReadyEntries $e -StableWindowHandles $h -AbandonedEntries $a }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[pscustomobject]$Pipeline,

		[Parameter(Mandatory = $true)]
		[int]$ReadyDesktopNumber,

		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[array]$ReadyEntries,

		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[array]$StableWindowHandles,

		[Parameter()]
		[AllowNull()]
		[AllowEmptyCollection()]
		[array]$AbandonedEntries
	)

	$displayDesktop = [int]$ReadyDesktopNumber + $Pipeline.DesktopOffset
	try {
		# Wait time so far belongs to Wait; the work below to Position and Snap.
		& $Pipeline.RecordPhase 'Wait'
		if ($Pipeline.SpinnerActive) { Loading-Spinner -Pause }

		$candidateHandles = New-Object 'System.Collections.Generic.HashSet[IntPtr]'
		foreach ($stableHandle in @($StableWindowHandles)) {
			if ($null -ne $stableHandle -and $stableHandle -ne [IntPtr]::Zero) { [void]$candidateHandles.Add([IntPtr]$stableHandle) }
		}
		$readyStates = @{}
		$readyCount = 0
		foreach ($ready in @($ReadyEntries)) {
			if ($null -eq $ready -or $null -eq $ready.Window -or $null -eq $ready.Window.Handle) { continue }
			$readyCount++
			[void]$candidateHandles.Add($ready.Window.Handle)
			$readyStates[$ready.Window.Handle] = @{
				Title  = $ready.Window.Title
				X      = $ready.Window.Left
				Y      = $ready.Window.Top
				Width  = $ready.Window.Width
				Height = $ready.Window.Height
			}
		}
		if ($readyCount -eq 0 -or $candidateHandles.Count -eq 0) { return }

		Write-LogDebug " Desktop [$displayDesktop] is ready while the rest still load - positioning and snapping it now ($readyCount window(s))" -Style Success

		# The WHOLE layout, restricted to this desktop's entries: duplicate keys are counted
		# across desktops, so an entry whose twin sits on another desktop claims one window.
		$desktopLayoutParams = @{
			LayoutConfig          = $Pipeline.LayoutConfig
			DesktopNumbers        = @([int]$ReadyDesktopNumber)
			MonitorInfo           = $Pipeline.MonitorInfo
			MonitorConfig         = $Pipeline.MonitorConfig
			Claims                = $Pipeline.Claims.WithCandidates($candidateHandles)
			ExpectedWindowState   = $readyStates
			DesktopOffset         = $Pipeline.DesktopOffset
			KeepPositionedWindows = $true
		}
		# An entry the wait already abandoned on this desktop gets one search here, not the
		# 1.5 s not-found ladder - inside the wait that ladder would delay the other desktops.
		if ($AbandonedEntries -and @($AbandonedEntries).Count -gt 0) {
			$desktopLayoutParams["AbandonedEntries"] = @($AbandonedEntries)
		}

		# Only what was actually placed counts as done. An entry that came back Not Found
		# here is finished by the pass after the wait, exactly as before pipelining; its
		# row is dropped so the shortfall tally is not counted twice.
		$desktopResults = @(Set-WindowLayouts @desktopLayoutParams)
		$placedHere = 0
		foreach ($desktopResult in $desktopResults) {
			if ($desktopResult.Status -ne 'Configured') { continue }
			$Pipeline.PipelinedResults.Add($desktopResult)
			$placedHere++
			if (-not [string]::IsNullOrEmpty($desktopResult.EntryKey)) {
				[void]$Pipeline.PipelinedEntryKeys.Add([string]$desktopResult.EntryKey)
			}
			if ($null -ne $desktopResult.Handle -and $desktopResult.Handle -ne [IntPtr]::Zero) {
				[void]$Pipeline.Claims.Excluded.Add([IntPtr]$desktopResult.Handle)
			}
		}
		if ($placedHere -eq 0) {
			Write-LogDebug " Desktop [$displayDesktop]: no entry could be placed yet - left to the pass after the wait" -Style Warning
			return
		}
		if ($placedHere -lt $readyCount) {
			Write-LogDebug " Desktop [$displayDesktop]: placed $placedHere of $readyCount entries now - the rest follow after the wait" -Style Warning
		}

		$null = Resize-PositionedWindows -DesktopNumbers @($displayDesktop)
		& $Pipeline.RecordPhase 'Position'

		# -DesktopOffset 0 for the same reason as the main snap pass in Set-WorkspaceWindowLayout:
		# the tracked desktop numbers already carry the offset.
		$null = Snap-AllWindows -DesktopOffset 0 -DesktopCount $Pipeline.DesktopCount -DesktopNumbers @($displayDesktop) -ZoneReset $Pipeline.ZoneReset
		$desktopSnap = $script:LastSnapAllWindowsResult
		if ($desktopSnap -and $desktopSnap.FailedWindows) {
			foreach ($desktopFailure in @($desktopSnap.FailedWindows)) {
				$Pipeline.PipelinedSnapFailures.Add($desktopFailure)
			}
		}
		& $Pipeline.RecordPhase 'Snap'

		$Pipeline.PipelinedDesktops[[int]$ReadyDesktopNumber] = $true
	}
	catch {
		# Nothing was marked done, so the tail after the wait positions this desktop with
		# the others.
		Write-LogDebug " Per-desktop pass for desktop [$displayDesktop] failed - leaving it to the main pass: $($_.Exception.Message)" -Style Warning
	}
	finally {
		if ($Pipeline.SpinnerActive) { Loading-Spinner -Resume }
	}
}
