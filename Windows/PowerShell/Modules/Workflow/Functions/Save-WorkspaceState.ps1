function Save-WorkspaceState {
	<#
	.SYNOPSIS
		Records what an Open-Workspace invocation actually opened, so Close-Workspace can close it.

	.DESCRIPTION
		Called by Open-Workspace once per workspace, after its actions have run. Given the window
		handles and Windows Terminal tabs that existed BEFORE the open, this enumerates what exists
		now and stores the difference: the windows that appeared and the terminal tabs that appeared
		are, by definition, the ones this open produced.

		Deriving ownership from the delta rather than from WorkspaceActions is the whole point. A
		single-instance app is only ever recorded against the open that actually launched it -
		Obsidian already running because an earlier workspace opened it produces no new window, so it
		never enters a later workspace's entry and survives that workspace being closed. A
		config-derived record would list it under every workspace that names it and lose that.

		Terminal tabs are counted, not set-differenced, so a second tab with a title that already
		existed is still recognised as new.

		A plain open REPLACES the file: it resets the virtual desktops, so no earlier open survives
		it and the tracker describes exactly this workspace. Every -Alongside open APPENDS, including
		for a name that is already tracked - that is a genuinely separate instance with its own
		windows, and Close-Workspace closes all of them.

		Writing is best-effort. Any failure is logged as a warning and swallowed, because a snapshot
		write must never fail an otherwise successful workspace open; the cost is that
		Close-Workspace will report that workspace as untracked.

	.PARAMETER Workspace
		Name of the workspace this entry belongs to.

	.PARAMETER ExistingWindowHandles
		The window handles that existed before the open. Accepts what Open-Workspace already builds
		(a HashSet[IntPtr]), raw handle values, or window objects exposing .Handle.

	.PARAMETER ExistingTerminalTabs
		The Get-TerminalTabSnapshot taken before the open (window handle -> tab titles).

	.PARAMETER PreCapturedTerminalTabs
		The matching AFTER snapshot, taken by the caller while the terminal was still on the visible
		desktop. Forwarded to Get-WorkspaceOpenDelta, which otherwise reads it itself and pays a
		desktop round trip to do so - see that function's help.

	.PARAMETER DesktopOffset
		Desktop offset this open used (0 normally, +N for -Alongside). Recorded for context.

	.PARAMETER Alongside
		Present when the workspace was opened alongside existing desktops. Controls whether the file
		is appended to (preserve the workspaces already on screen) or replaced.

	.PARAMETER AdoptUnclaimed
		Forwarded to Get-WorkspaceOpenDelta: also claim what was already on screen, so an app that
		was already running becomes closable. Correct for the first workspace of a plain run only -
		see that function's help.

	.PARAMETER Append
		Add to the tracker instead of replacing it, without implying -Alongside. Used for the second
		and later workspaces of a single plain "Open-Workspace a, b" run, which would otherwise each
		replace the previous one's entry.

	.PARAMETER Entry
		Low-level form: write exactly these entries, replacing the file. Used by Close-Workspace to
		persist what remains open after a teardown, and by Kill-All to clear the tracker. Pass an
		empty array to clear it.

	.PARAMETER StatePath
		Full path to the state file. Defaults to Get-WorkspaceStatePath.

	.EXAMPLE
		Save-WorkspaceState -Workspace 'Server' -ExistingWindowHandles $before -ExistingTerminalTabs $tabsBefore
		Records every window and terminal tab that appeared while the Server workspace opened.

	.EXAMPLE
		Save-WorkspaceState -Entry $survivingEntries
		Rewrites the tracker with only the entries that are still open.
	#>
	[CmdletBinding(DefaultParameterSetName = 'Record')]
	param(
		[Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'Record')]
		[string]$Workspace,

		[Parameter(ParameterSetName = 'Record')]
		[object]$ExistingWindowHandles,

		[Parameter(ParameterSetName = 'Record')]
		[hashtable]$ExistingTerminalTabs,

		[Parameter(ParameterSetName = 'Record')]
		[hashtable]$PreCapturedTerminalTabs,

		[Parameter(ParameterSetName = 'Record')]
		[int]$DesktopOffset = 0,

		[Parameter(ParameterSetName = 'Record')]
		[switch]$Alongside,

		[Parameter(ParameterSetName = 'Record')]
		[switch]$AdoptUnclaimed,

		[Parameter(ParameterSetName = 'Record')]
		[switch]$Append,

		[Parameter(Mandatory = $true, ParameterSetName = 'Entries')]
		[AllowEmptyCollection()]
		[object[]]$Entry,

		[Parameter()]
		[string]$StatePath
	)

	if ([string]::IsNullOrWhiteSpace($StatePath)) {
		$StatePath = Get-WorkspaceStatePath
	}

	try {
		if ($PSCmdlet.ParameterSetName -eq 'Entries') {
			$entries = @($Entry | Where-Object { $_ })
		}
		else {
			$recorded = Get-WorkspaceOpenDelta -Workspace $Workspace `
				-ExistingWindowHandles $ExistingWindowHandles `
				-ExistingTerminalTabs $ExistingTerminalTabs `
				-PreCapturedTerminalTabs $PreCapturedTerminalTabs `
				-DesktopOffset $DesktopOffset `
				-Alongside:$Alongside `
				-AdoptUnclaimed:$AdoptUnclaimed

			# A plain open reset the desktops, so nothing that was tracked before it is still on
			# screen - start clean. -Alongside added to what was already there, so keep it all.
			# -Append covers the remaining case: the second and later workspaces of a single plain
			# "Open-Workspace a, b" run, which must add to the session the first one defined instead
			# of replacing its entry and leaving it untracked.
			$entries = @()
			if ($Alongside -or $Append) {
				$existingState = Get-WorkspaceState -StatePath $StatePath
				if ($existingState) {
					$entries = @($existingState.Entries)
				}
			}
			$entries += $recorded
		}

		$stateDirectory = Split-Path -Path $StatePath -Parent
		if ($stateDirectory -and -not (Test-Path -LiteralPath $stateDirectory)) {
			New-Item -ItemType Directory -Path $stateDirectory -Force -ErrorAction Stop | Out-Null
		}

		Set-Content -LiteralPath $StatePath -Value (Format-WorkspaceStateContent -Entry $entries) -NoNewline -Encoding UTF8 -ErrorAction Stop

		if ($PSCmdlet.ParameterSetName -eq 'Record') {
			Write-LogDebug " [Save-WorkspaceState] Recorded [$Workspace] => $(@($recorded.Windows).Count) window(s), $(@($recorded.TerminalTabs).Count) terminal tab(s)" -Style Success
		}
	}
	catch {
		# Never fail an otherwise successful open because the tracker could not be written.
		Write-LogWarning "Could not write the workspace state file: $($_.Exception.Message)" -NoLeadingNewline
	}
}
