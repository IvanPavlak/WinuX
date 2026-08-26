function Get-WorkspaceOpenProtection {
	<#
	.SYNOPSIS
		Resolves what a plain workspace open must leave alone: live alongside workspaces.

	.DESCRIPTION
		A plain Open-Workspace resets the virtual desktops and replaces the tracker, which is
		correct for everything it owns - but an -Alongside workspace standing on desktops to the
		right is NOT something a plain rerun opened, and without protection the rerun destroys it
		three ways at once: the desktop resize removes its desktops, the layout pass steals its
		windows (layout entries match by process/title, and "Browser" matches any browser window),
		and the tracker/CurrentLayout writes wipe its records, leaving it unclosable.

		This function derives the protection set the same way Close-Workspace derives what a
		teardown must spare: from the tracker Open-Workspace wrote, never from configuration.
		Every tracked entry with Alongside = $true is checked against the live windows; an entry
		that still has at least one live window is PRESERVED - its tracker entry is carried
		forward verbatim and its resolved live window handles become untouchable for the whole
		open. Entries whose windows are all gone are not preserved (there is nothing left to
		protect, and the tracker describes what is open). Plain entries are never preserved: a
		plain rerun replaces the plain session by design.

		Records are resolved with the same ladder Close-Workspace uses: exact handle first, then
		same ProcessId + ProcessName (Electron applications recreate their window without
		restarting), then same ProcessName + exact Title (the application restarted outright).
		The third step shares Close-Workspace's accepted false-positive risk: two workspaces can
		have identically titled windows of the same process, and a re-resolution by title may
		claim the wrong one. A live recorded handle needs no such guard and cannot be wrong.

		The common case - no alongside workspace open - pays one tracker file parse and nothing
		else: the function short-circuits to $null before any window enumeration.

	.PARAMETER StatePath
		Full path to the tracker file. Defaults to Get-WorkspaceStatePath. Mainly a test seam.

	.OUTPUTS
		$null when there is nothing to preserve (no tracker, no alongside entries, or none with a
		live window). Otherwise a [pscustomobject] with:
		- Entries       : the preserved tracker entries, verbatim, for Save-WorkspaceState to seed
		- WindowHandles : HashSet[IntPtr] of the resolved live window handles those entries own

	.EXAMPLE
		$protection = Get-WorkspaceOpenProtection
		if ($protection) { "preserving $(@($protection.Entries).Count) alongside workspace(s)" }

	.NOTES
		Consumed by Open-Workspace on plain (non-Alongside) opens, which threads the handle set
		through Set-WorkspaceWindowLayout, Set-WindowLayouts, Open-Browser and the tracker write.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter()]
		[string]$StatePath
	)

	$stateParams = @{}
	if (-not [string]::IsNullOrWhiteSpace($StatePath)) { $stateParams['StatePath'] = $StatePath }

	$state = Get-WorkspaceState @stateParams
	if (-not $state) { return $null }

	$alongsideEntries = @($state.Entries | Where-Object { $_ -and [bool]$_.Alongside })
	if ($alongsideEntries.Count -eq 0) { return $null }

	# Something alongside is tracked - only now is a window enumeration worth paying for.
	if (Get-Command Clear-WindowCache -ErrorAction SilentlyContinue) { Clear-WindowCache }
	$liveWindows = @(Get-WindowHandle -ErrorAction SilentlyContinue)

	# Close-Workspace's resolution ladder, applied to the records of a workspace that must
	# SURVIVE this open instead of one being torn down. Step 3 (same process name + exact
	# title) carries the same accepted false-positive risk as there: two workspaces routinely
	# hold identically titled windows, so a title re-resolution can claim the plain session's
	# own window. A live recorded handle is unambiguous and taken as-is.
	$resolveTrackedWindow = {
		param($Record, $LiveWindows)

		$recordedHandle = [int64]$Record.Handle

		$byHandle = @($LiveWindows | Where-Object { [int64]$_.Handle -eq $recordedHandle })[0]
		if ($byHandle) { return $byHandle }

		if ([string]::IsNullOrWhiteSpace($Record.ProcessName)) { return $null }

		if ([int64]$Record.ProcessId -gt 0) {
			$byProcess = @($LiveWindows | Where-Object {
					[int64]$_.ProcessId -eq [int64]$Record.ProcessId -and [string]$_.ProcessName -eq [string]$Record.ProcessName
				})[0]
			if ($byProcess) { return $byProcess }
		}

		if (-not [string]::IsNullOrWhiteSpace($Record.Title)) {
			$byTitle = @($LiveWindows | Where-Object {
					[string]$_.ProcessName -eq [string]$Record.ProcessName -and [string]$_.Title -eq [string]$Record.Title
				})[0]
			if ($byTitle) { return $byTitle }
		}

		return $null
	}

	$preservedEntries = [System.Collections.Generic.List[object]]::new()
	# IntPtr is the currency every consumer compares in (Get-WindowHandle returns IntPtr
	# handles); tracker records hold int64 and are cast per resolution below.
	$protectedHandles = New-Object 'System.Collections.Generic.HashSet[IntPtr]'

	foreach ($entry in $alongsideEntries) {
		$resolvedHandles = [System.Collections.Generic.List[IntPtr]]::new()

		foreach ($record in @($entry.Windows)) {
			if (-not $record) { continue }

			$resolvedWindow = & $resolveTrackedWindow $record $liveWindows
			if ($resolvedWindow) {
				$resolvedHandles.Add([IntPtr][int64]$resolvedWindow.Handle)
			}
		}

		# One live window is enough: the workspace is still standing, so ALL of it is kept -
		# the entry verbatim (records whose windows died stay recorded; Close-Workspace
		# already tolerates that staleness) and every handle that did resolve.
		if ($resolvedHandles.Count -gt 0) {
			$preservedEntries.Add($entry)
			foreach ($resolvedHandle in $resolvedHandles) {
				[void]$protectedHandles.Add($resolvedHandle)
			}
		}
	}

	if ($preservedEntries.Count -eq 0) { return $null }

	return [pscustomobject]@{
		Entries       = $preservedEntries.ToArray()
		WindowHandles = $protectedHandles
	}
}
