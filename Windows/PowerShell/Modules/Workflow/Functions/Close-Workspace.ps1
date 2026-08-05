function Close-Workspace {
	<#
	.SYNOPSIS
		Closes everything a workspace opened - one level above Close-Project.

	.DESCRIPTION
		The counterpart to Open-Workspace. Where Close-Project closes one project's resources and
		deliberately leaves workspace-level applications running, Close-Workspace tears down the
		whole workspace: every window and every Windows Terminal tab that the open produced.

		Ownership comes from the tracker Open-Workspace writes (Save-WorkspaceState), never from
		WorkspaceActions - configuration cannot express which instance of a shared application
		belongs to which workspace, and guessing is what this exists to avoid.

		A plain open also claims what was already on screen when it finishes, because it reset the
		virtual desktops first: the screen IS that workspace. An -Alongside open claims only what it
		actually created, because it added to a screen other workspaces are already using. That
		asymmetry is what makes both cases correct. Obsidian launched by workspace A stays A's when B
		is opened alongside, so closing B leaves it running; but an application that was already
		running when a plain open started is claimed by it, which is the only thing that stops such
		an application from surviving every teardown forever. Processes named in
		Universal.VisibleWindowExclusions - the list Kill-All uses for the same purpose - are never
		claimed that way, so a plain open does not take ownership of the terminal window it was typed
		in, of Rainmeter, or of anything else that merely happened to be running.

		The same tracker is why teardown works identically for -Alongside opens: an entry records
		what one invocation did, whichever mode it ran in.

		Nothing is closed that the tracker does not list, and nothing is guessed. With no tracker at
		all - a workspace opened before this feature existed, from another session, or before a
		reboot - the command reports that and stops rather than falling back to configuration, which
		would reintroduce exactly the ownership ambiguity the tracker removes.

		A workspace also owns the virtual desktops it opened on, which is the second claim: a window
		sitting on one of them goes even when the diff never recorded it, and the desktops themselves
		are removed at the end. Which desktops those are is resolved from where the workspace's own
		windows are standing at teardown time, never from a stored index - desktop indexes shift
		whenever a desktop to their left is removed, so a stored one goes stale and acting on it would
		reach onto another workspace's desktop. Desktops belonging to a workspace that stays open are
		off limits to both halves of that.

		What happens, per selected workspace:

		- Windows are matched by handle, then re-resolved by process and by exact process name plus
		  title when the handle has gone stale (Electron applications recreate their windows). A window
		  matched by its own live handle is unambiguously this workspace's; only a re-resolved one is
		  held back when a workspace that stays open claims that process-and-title identity, because
		  two workspaces routinely have identically titled windows (open two of them and each has a
		  "YouTube - Mozilla Firefox").
		- Anything else standing on this workspace's own desktops is closed too, unless a workspace
		  that stays open claims it by handle, by identity, or by owning that desktop.
		- Each window is asked to close with WM_CLOSE, exactly as Close-Project does, so unsaved
		  work still prompts. A window that refuses is reported and left alone - never force-killed.
		- Terminal tabs are closed through their UI Automation close button (no focus stealing, no
		  synthesized keystrokes), and the window is left to disappear with its last tab, because a
		  WM_CLOSE on a multi-tab window raises a confirmation dialog. A terminal window the
		  workspace OPENED (the -Alongside flow creates one) belongs to it whole, so every tab in it
		  goes; a window it merely put tabs into keeps everything else. Either way, an owned window
		  still standing after the tab pass is closed directly rather than left running.
		- Reading those tabs can require bringing the workspace's virtual desktop on screen first:
		  Windows Terminal only composes its tab strip while its desktop is visible, and reports no
		  tabs at all otherwise. The view is put back before the desktop sweep, and a terminal that
		  is already on screen never triggers a switch.
		- The tab this command is running in, when it belongs to the workspace being closed, is
		  closed last through the process-exit seam - it cannot close itself mid-run.
		- The workspace's virtual desktops are removed, then any desktop this teardown emptied without
		  ever having had a window on it, and focus returns to the calling terminal. The workspace's own
		  desktops are named explicitly rather than swept as "empty", because the one window a teardown
		  cannot close before that point is the shell it is running in - and when the workspace opened
		  that shell, its desktop is never empty at sweep time and nothing would ever tidy it. Removing
		  the desktop relocates that window instead of stranding it.

		The menu lists one row per tracked INSTANCE. Opening the same workspace twice - once plainly and
		once alongside - produces two entries describing two separate sets of windows sitting side by
		side, so they are offered separately and either can be closed on its own. A name with a single
		instance keeps its bare name; several instances of one name are labelled by where they are, e.g.

			[1] Example (plain, desktop 1)
			[2] Example (alongside, desktop 6)
			[3] WinuX

		Naming a whole workspace still closes every instance of it, so "Close-Workspace Example" ends
		that workspace entirely and remains usable from a script. Pass a full label to target one
		exactly, or pick several menu rows at once - the menu is multi-select.

		There is no confirmation prompt: closing is not destructive and it is the caller's job to
		know when to run it. Use -WhatIf to see the full plan without touching anything.

	.PARAMETER Workspace
		Name of the workspace(s) to close, or the full label of a single instance. A bare name closes
		every tracked instance of it. Omit for an interactive menu listing the instances currently
		tracked as open. Only tracked names and labels are offered or accepted - a workspace that is
		configured but not open is not something this command can close.

	.PARAMETER StatePath
		Full path to the tracker file. Defaults to Get-WorkspaceStatePath. Mainly a test seam.

	.EXAMPLE
		Close-Workspace
		Lists the workspaces currently open and closes the selected one(s).

	.EXAMPLE
		Close-Workspace Server
		Closes every tracked instance of the Server workspace, however it was opened.

	.EXAMPLE
		Close-Workspace 'Example (alongside, desktop 6)'
		Closes one instance of a workspace that is open twice, leaving the other one running.

	.EXAMPLE
		Close-Workspace Server -WhatIf
		Reports every window, tab and desktop that would be closed, and changes nothing.

	.EXAMPLE
		Close-Workspace -Workspace Server, WinuX
		Closes both workspaces in one pass.

	.NOTES
		Counterpart to Open-Workspace; one level above Close-Project, which it does not replace -
		Close-Project remains the way to swap projects inside a workspace that stays open.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	param(
		[Parameter(Position = 0)]
		[string[]]$Workspace,

		[Parameter()]
		[string]$StatePath
	)

	# Graceful close, same as Close-Project. Each closing function in the repository declares its
	# own guarded P/Invoke type; there is no shared native close seam to reuse yet.
	if (-not ([System.Management.Automation.PSTypeName]'CloseWorkspaceWin32').Type) {
		Add-Type @"
			using System;
			using System.Runtime.InteropServices;
			public class CloseWorkspaceWin32 {
				[DllImport("user32.dll")]
				public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

				public const uint WM_CLOSE = 0x0010;
			}
"@
	}

	$stateParams = @{}
	if (-not [string]::IsNullOrWhiteSpace($StatePath)) { $stateParams['StatePath'] = $StatePath }

	$state = Get-WorkspaceState @stateParams

	if (-not $state) {
		Write-LogWarning "Nothing is tracked as open, so there is nothing to close!"
		Write-LogDebug " Close-Workspace closes only what Open-Workspace recorded. A workspace opened before this feature existed, opened from another session, or left over from before a reboot has no record and is not closed by guesswork." -Style Warning
		return
	}

	$trackedEntries = @($state.Entries)

	if ($trackedEntries.Count -eq 0) {
		Write-LogWarning "No workspaces are currently open!"
		return
	}

	# One menu row per tracked INSTANCE, not per name. Opening the same workspace twice - once plainly
	# and once alongside, which "w Example -Browser Chrome" then "w Example -Browser Edge -Alongside"
	# does - produces two entries describing two separate sets of windows sitting side by side, and a
	# menu listing "Example" once could only ever offer to close both.
	#
	# A name with a single instance keeps its bare name, so the everyday menu gains nothing to read.
	# Several instances of one name are labelled by WHERE they are, because that is what the choice is
	# actually between when two of them are on screen at once. The desktop number is 1-based, matching
	# the layout-file convention, so it names the desktop the workspace starts on.
	$instances = [System.Collections.Generic.List[object]]::new()
	foreach ($trackedEntry in $trackedEntries) {
		$instances.Add([pscustomobject]@{
				Entry = $trackedEntry
				Name  = [string]$trackedEntry.Workspace
				Label = [string]$trackedEntry.Workspace
			})
	}

	$instanceCountByName = @{}
	foreach ($instance in $instances) {
		$nameKey = $instance.Name.ToLowerInvariant()
		$instanceCountByName[$nameKey] = 1 + [int]$instanceCountByName[$nameKey]
	}

	$usedLabels = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($instance in $instances) {
		if ($instanceCountByName[$instance.Name.ToLowerInvariant()] -gt 1) {
			$mode = if ($instance.Entry.Alongside) { 'alongside' } else { 'plain' }
			$instance.Label = "{0} ({1}, desktop {2})" -f $instance.Name, $mode, ([int]$instance.Entry.DesktopOffset + 1)
		}

		# Resolve-Selection de-duplicates what it returns, so two rows sharing a label would collapse
		# into one and silently spare an instance. Offsets make that practically impossible, but a
		# hand-edited or half-written tracker must not be able to cause it.
		if (-not $usedLabels.Add($instance.Label)) {
			$suffix = 2
			while (-not $usedLabels.Add("$($instance.Label) #$suffix")) { $suffix++ }
			$instance.Label = "$($instance.Label) #$suffix"
		}
	}

	$instanceLabels = @($instances | ForEach-Object { $_.Label })
	$trackedNames = @($instances | ForEach-Object { $_.Name } | Select-Object -Unique)
	$hasWorkspaceArgument = @($Workspace | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0

	$resolveParams = @{
		InputObject              = $Workspace
		OptionList               = $instanceLabels
		MenuTitle                = "[Open workspaces to close]"
		PromptMessage            = "Enter workspace(s) to close or press [Enter] to cancel"
		AllowEmptyPromptResponse = $true
		AllowMultipleSelections  = $true
	}

	# A bare workspace name still means every instance of it, so "Close-Workspace Example" keeps
	# ending that workspace entirely and stays usable from a script. Resolve-Selection only knows the
	# instance labels, though, so a bare name has to be recognised here rather than offered to it -
	# and it also splits typed input on whitespace, which a label contains. Hence: names are matched
	# by this function, labels are picked from the menu by number or passed in whole as an argument.
	$requestedNames = @()
	$menuSelections = @($Workspace)
	if ($hasWorkspaceArgument) {
		$requestedNames = @($Workspace | Where-Object { $name = $_; @($trackedNames | Where-Object { $_ -ieq $name }).Count -gt 0 })
		# Anything that named a whole workspace is handled here; the rest is for Resolve-Selection to
		# resolve as a label (or reject as invalid).
		$menuSelections = @($Workspace | Where-Object { $item = $_; @($requestedNames | Where-Object { $_ -ieq $item }).Count -eq 0 })
	}

	# Resolve-Selection answers [Enter] with $null, and @($null) is a one-element array holding
	# nothing - filtering is what makes an empty selection actually count as none. It is only asked at
	# all when there is something left for it to resolve: handing it an empty InputObject after every
	# argument resolved to a name would pop the interactive menu instead.
	$selectedLabels = @()
	if (-not $hasWorkspaceArgument -or @($menuSelections | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
		$resolveParams['InputObject'] = $menuSelections
		$selectedLabels = @(Resolve-Selection @resolveParams | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
	}

	$selectedWorkspaces = @(@($requestedNames) + @($selectedLabels) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

	if ($selectedWorkspaces.Count -eq 0) {
		# The menu only ever lists open workspaces, so a named workspace that resolved to nothing is
		# a workspace that is not open - a different problem from cancelling the menu.
		if ($hasWorkspaceArgument) {
			Write-LogWarning "None of the requested workspace(s) are open! Currently open => $($instanceLabels -join ', ')"
		}
		else {
			Write-LogWarning "No workspaces selected to close!"
		}
		return
	}

	# An instance is closing when its own label was picked, or when its whole workspace was named.
	$isSelected = {
		param($Instance)
		[bool]@($selectedWorkspaces | Where-Object { $_ -ieq $Instance.Label -or $_ -ieq $Instance.Name }).Count
	}

	$closingEntries = @($instances | Where-Object { & $isSelected $_ } | ForEach-Object { $_.Entry })
	$survivingEntries = @($instances | Where-Object { -not (& $isSelected $_) } | ForEach-Object { $_.Entry })

	# A record whose handle has gone stale is re-resolved by process or title below, and that search
	# must never reach into a workspace that is staying open. Claim both the handles and the
	# process/title identities of every surviving entry up front.
	#
	# The identity set is deliberately only consulted for a RE-RESOLVED window, never for one matched
	# by its own recorded handle. Process name plus title is not unique across workspaces: open WinuX
	# and FuturamaSoft and both have a "YouTube - Mozilla Firefox" and a "New chat - Claude - Mozilla
	# Firefox" window. Applying the guard to an exact handle match therefore left the closing
	# workspace's own YouTube and AI windows on screen, protected by the OTHER workspace's identically
	# titled ones. A live recorded handle is unambiguous and needs no guard.
	$protectedHandles = New-Object 'System.Collections.Generic.HashSet[int64]'
	$protectedIdentities = New-Object 'System.Collections.Generic.HashSet[string]'
	$windowIdentity = { param($ProcessName, $Title) ("{0}|{1}" -f [string]$ProcessName, [string]$Title).ToLowerInvariant() }

	foreach ($survivingEntry in $survivingEntries) {
		foreach ($survivingWindow in @($survivingEntry.Windows)) {
			if (-not $survivingWindow) { continue }
			[void]$protectedHandles.Add([int64]$survivingWindow.Handle)
			[void]$protectedIdentities.Add((& $windowIdentity $survivingWindow.ProcessName $survivingWindow.Title))
		}
	}

	# Which desktops a set of windows is on RIGHT NOW. Always observed live, never stored: desktop
	# indexes shift whenever a desktop to their left is removed, so a recorded index goes stale, and
	# acting on a stale one would reach onto another workspace's desktop. Handles are stable, so
	# resolving them at teardown time is the one answer that cannot be wrong.
	$liveDesktopsOf = {
		param($Handle)

		$desktops = New-Object 'System.Collections.Generic.HashSet[int]'
		foreach ($candidateHandle in @($Handle)) {
			$handleValue = [int64]$candidateHandle
			if ($handleValue -eq 0) { continue }

			$desktopIndex = Get-WindowDesktopIndex -WindowHandle ([IntPtr]$handleValue)
			if ($desktopIndex -ge 0) { [void]$desktops.Add([int]$desktopIndex) }
		}
		# Comma operator: returning the set bare lets PowerShell enumerate it, and a one-desktop
		# workspace - the common case - would arrive at the caller as a bare [int] with no .Contains().
		return , $desktops
	}

	# The desktops of every workspace that stays open. A workspace owns its desktops, so these are off
	# limits both to the desktop-membership claim below and to the desktop removal at the end.
	$protectedDesktops = New-Object 'System.Collections.Generic.HashSet[int]'
	foreach ($survivingEntry in $survivingEntries) {
		$survivingHandles = @(@($survivingEntry.Windows) | Where-Object { $_ } | ForEach-Object { [int64]$_.Handle })
		# Not wrapped in @(): the helper returns the set itself, and foreach enumerates it.
		$survivingDesktops = & $liveDesktopsOf $survivingHandles
		foreach ($survivingDesktop in $survivingDesktops) {
			[void]$protectedDesktops.Add([int]$survivingDesktop)
		}
	}

	# Reports HOW a record was matched as well as what it matched, because that decides whether the
	# survivor guard above applies. An exact handle match needs no guard at all; a re-resolution does.
	$resolveTrackedWindow = {
		param($Record, $LiveWindows)

		$recordedHandle = [int64]$Record.Handle

		# The handle is unambiguous for as long as the window lives.
		$byHandle = @($LiveWindows | Where-Object { [int64]$_.Handle -eq $recordedHandle })[0]
		if ($byHandle) { return [pscustomobject]@{ Window = $byHandle; Exact = $true } }

		# Past this point the recorded handle is gone and the window has to be recognised again.
		# Only a record that named a process can be: a title alone is not evidence of ownership.
		if ([string]::IsNullOrWhiteSpace($Record.ProcessName)) { return $null }

		# Same process, new window - Electron applications recreate a window without restarting.
		if ([int64]$Record.ProcessId -gt 0) {
			$byProcess = @($LiveWindows | Where-Object {
					[int64]$_.ProcessId -eq [int64]$Record.ProcessId -and [string]$_.ProcessName -eq [string]$Record.ProcessName
				})[0]
			if ($byProcess) { return [pscustomobject]@{ Window = $byProcess; Exact = $false } }
		}

		# Same process name and the exact same title - the application restarted outright. Exact,
		# because a loose match here would close a window this workspace never opened.
		if (-not [string]::IsNullOrWhiteSpace($Record.Title)) {
			$byTitle = @($LiveWindows | Where-Object {
					[string]$_.ProcessName -eq [string]$Record.ProcessName -and [string]$_.Title -eq [string]$Record.Title
				})[0]
			if ($byTitle) { return [pscustomobject]@{ Window = $byTitle; Exact = $false } }
		}

		return $null
	}

	if (Get-Command Clear-WindowCache -ErrorAction SilentlyContinue) { Clear-WindowCache }
	$liveWindows = @(Get-WindowHandle -ErrorAction SilentlyContinue)

	$postedWindows = [System.Collections.Generic.List[object]]::new()
	$ownedTerminalWindows = [System.Collections.Generic.List[object]]::new()
	$closedTabs = [System.Collections.Generic.List[string]]::new()
	$skippedWindows = [System.Collections.Generic.List[string]]::new()
	$refusedTabs = [System.Collections.Generic.List[string]]::new()
	$alreadyGoneCount = 0
	$ownTabRecord = $null
	$ownTabTerminalHandle = $null
	# Every window this teardown has already decided about, so the desktop-membership pass cannot
	# message a window twice or reconsider one a survivor claimed.
	$handledHandles = New-Object 'System.Collections.Generic.HashSet[int64]'
	# The desktops the closed workspaces owned, which go with them at the end.
	$closingDesktops = New-Object 'System.Collections.Generic.HashSet[int]'
	# Set only if reading a terminal's tabs required bringing another desktop on screen, so the view
	# can be put back exactly once at the end instead of flicking per window.
	$restoreDesktopIndex = $null

	$hostingTerminal = Resolve-HostingTerminalTab

	foreach ($entry in $closingEntries) {
		# One title per ENTRY, not per name: a workspace opened twice is torn down twice, and the
		# offset says which instance is going.
		$entryLabel = "Closing $([string]$entry.Workspace) Workspace"
		if ($entry.Alongside) {
			# Same 1-based desktop the menu labels an instance with, so the two never disagree about
			# which of two same-named workspaces is going.
			$entryLabel += " (opened alongside, desktop $([int]$entry.DesktopOffset + 1))"
		}

		Write-LogTitle $entryLabel

		# The live handles this entry still owns, which is what its desktop set is derived from below.
		$entryLiveHandles = [System.Collections.Generic.List[int64]]::new()

		# Windows Terminal windows this workspace OPENED belong to it whole. The -Alongside flow
		# creates a new terminal window and puts the workspace's tabs in it, so "the workspace owns
		# the window" is the accurate statement, not "the workspace owns some tabs in it".
		$ownedTerminalHandles = New-Object 'System.Collections.Generic.HashSet[int64]'
		foreach ($record in @($entry.Windows)) {
			if ($record -and [string]$record.ProcessName -eq 'WindowsTerminal') {
				[void]$ownedTerminalHandles.Add([int64]$record.Handle)

				# An owned terminal counts towards the desktop set even though the tab pass, not the
				# window pass, closes it. After an -Alongside open it is often the only window on the
				# workspace's first desktop, so leaving it out would lose that desktop entirely.
				if (@($liveWindows | Where-Object { [int64]$_.Handle -eq [int64]$record.Handle }).Count -gt 0) {
					$entryLiveHandles.Add([int64]$record.Handle)
				}
			}
		}

		foreach ($record in @($entry.Windows)) {
			if (-not $record) { continue }

			# Terminal windows go through the tab pass below instead: a WM_CLOSE on a multi-tab
			# window raises the "close all tabs?" confirmation, and the window goes away by itself
			# once its last tab is gone. Anything the tab pass fails to take down is caught by the
			# fallback after it, so a terminal window can never be silently left behind.
			if ([string]$record.ProcessName -eq 'WindowsTerminal') { continue }

			$resolved = & $resolveTrackedWindow $record $liveWindows

			if (-not $resolved) {
				$alreadyGoneCount++
				Write-LogDebug "  Already closed => [$($record.Title)]" -Style Step
				continue
			}

			$window = $resolved.Window
			$identity = & $windowIdentity $window.ProcessName $window.Title

			# The identity guard applies to a re-resolved window only - see the note where the sets are
			# built. A handle this entry recorded, still alive, is this entry's window, full stop.
			$claimedBySurvivor = $protectedHandles.Contains([int64]$window.Handle) -or
				(-not $resolved.Exact -and $protectedIdentities.Contains($identity))

			if ($claimedBySurvivor) {
				$skippedWindows.Add([string]$window.Title)
				Write-LogDebug "  Skipping [$($window.Title)] - a workspace that stays open claims it" -Style Warning
				continue
			}

			[void]$handledHandles.Add([int64]$window.Handle)
			# Recorded before the -WhatIf gate: a dry run still has to report which desktops would go.
			$entryLiveHandles.Add([int64]$window.Handle)

			if (-not $PSCmdlet.ShouldProcess("$($window.ProcessName) window [$($window.Title)]", "Close")) { continue }

			Write-LogDebug "  Closing window => [$($window.Title)]" -Style Step
			[void][CloseWorkspaceWin32]::PostMessage([IntPtr]$window.Handle, [CloseWorkspaceWin32]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)

			$postedWindows.Add([PSCustomObject]@{
					Workspace = [string]$entry.Workspace
					Handle    = [int64]$window.Handle
					Title     = [string]$window.Title
				})
		}

		# Second claim: this workspace's own virtual desktops. A workspace owns the desktops it opened
		# on, so a window sitting on one of them belongs to it even when the handle diff never recorded
		# it - a browser window that was already open and got reused, a dialog an action spawned
		# indirectly, anything that had no top-level window yet at capture time. This is what makes
		# "everything on that workspace's desktops goes" true rather than approximately true.
		#
		# Which desktops those are is answered by where this entry's OWN windows are standing right now,
		# so the set is correct even if desktop indexes have shifted since the open. When none of its
		# windows survives there is nothing to derive from and nothing left to close anyway; the
		# emptied-desktop sweep at the end catches the desktops in that case.
		$ownDesktops = & $liveDesktopsOf @($entryLiveHandles)

		foreach ($ownDesktop in $ownDesktops) {
			if (-not $protectedDesktops.Contains([int]$ownDesktop)) { [void]$closingDesktops.Add([int]$ownDesktop) }
		}

		foreach ($liveWindow in $liveWindows) {
			if (-not $liveWindow) { continue }

			$liveHandle = [int64]$liveWindow.Handle
			if ($liveHandle -eq 0) { continue }
			if ($handledHandles.Contains($liveHandle)) { continue }

			# Terminal windows are the tab pass's business either way: closing one wholesale because it
			# stands on this workspace's desktop would take tabs the workspace never opened.
			if ([string]$liveWindow.ProcessName -eq 'WindowsTerminal') { continue }

			# A workspace that stays open keeps what it actually recorded. Its process-and-title
			# identities are deliberately NOT consulted here: identity is the weak signal that caused
			# the bug this pass exists to finish fixing, and the desktop already discriminates - a
			# survivor's windows are on the survivor's desktops, which are excluded below.
			if ($protectedHandles.Contains($liveHandle)) { continue }

			$liveDesktop = Get-WindowDesktopIndex -WindowHandle ([IntPtr]$liveHandle)
			if ($liveDesktop -lt 0) { continue }
			if ($protectedDesktops.Contains([int]$liveDesktop)) { continue }
			if (-not $ownDesktops.Contains([int]$liveDesktop)) { continue }

			[void]$handledHandles.Add($liveHandle)

			if (-not $PSCmdlet.ShouldProcess("$($liveWindow.ProcessName) window [$($liveWindow.Title)] on desktop $liveDesktop", "Close")) { continue }

			Write-LogDebug "  Closing window on this workspace's desktop $liveDesktop => [$($liveWindow.Title)]" -Style Step
			[void][CloseWorkspaceWin32]::PostMessage([IntPtr]$liveHandle, [CloseWorkspaceWin32]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)

			$postedWindows.Add([PSCustomObject]@{
					Workspace = [string]$entry.Workspace
					Handle    = $liveHandle
					Title     = [string]$liveWindow.Title
				})
		}

		# One UI Automation read per Windows Terminal window rather than per tab: reading the tab
		# strip is a tree scan, and a workspace routinely tracks several tabs in the same window.
		$tabsByWindow = @{}
		foreach ($tabRecord in @($entry.TerminalTabs)) {
			if (-not $tabRecord) { continue }
			$tabWindowHandle = [int64]$tabRecord.WindowHandle
			if (-not $tabsByWindow.ContainsKey($tabWindowHandle)) { $tabsByWindow[$tabWindowHandle] = @() }
			$tabsByWindow[$tabWindowHandle] += [string]$tabRecord.Title
		}

		# An owned window is visited even when it recorded no tabs at all. The tab record comes from
		# a UI Automation read taken as the open finished, and a window that had already been moved
		# to another virtual desktop by the layout pass may not expose its tab strip then - a window
		# whose teardown depended on that read would simply be left running.
		$terminalWindowHandles = @(@($ownedTerminalHandles) + @($tabsByWindow.Keys) | Select-Object -Unique)

		foreach ($tabWindowHandle in $terminalWindowHandles) {
			$terminalHandle = [IntPtr]$tabWindowHandle
			$ownsWholeWindow = $ownedTerminalHandles.Contains([int64]$tabWindowHandle)

			# Registered before anything can fail or skip below - the fallback pass exists exactly
			# for the paths that do not get to close this window's tabs.
			if ($ownsWholeWindow) {
				$ownedTerminalWindows.Add([PSCustomObject]@{
						Workspace = [string]$entry.Workspace
						Handle    = [int64]$tabWindowHandle
					})
			}

			$liveTabTitles = Get-WindowsTerminalTabTitles -WindowHandle $terminalHandle

			if ($null -eq $liveTabTitles) {
				# Windows Terminal hosts its tab strip in a XAML island that is only composed while
				# its virtual desktop is the visible one. Off screen, UI Automation reports the
				# window as having no descendants at all - no tabs to read and no close buttons to
				# invoke - and a workspace's terminal is by definition parked on the workspace's own
				# desktop once the layout pass has moved it. Bring that desktop up and ask again;
				# the view is put back after every entry has been processed.
				$previousDesktop = Ensure-DesktopVisible -WindowHandle $terminalHandle
				if ($null -ne $previousDesktop -and $null -eq $restoreDesktopIndex) {
					$restoreDesktopIndex = $previousDesktop
				}

				$liveTabTitles = Get-WindowsTerminalTabTitles -WindowHandle $terminalHandle
			}

			if ($null -eq $liveTabTitles) {
				# Still unreadable with the desktop on screen. An owned window is this workspace's to
				# close either way, so the fallback below takes it; a window that merely holds
				# tracked tabs is left alone, because closing it whole would take tabs that are not
				# ours.
				if (-not $ownsWholeWindow) {
					foreach ($tabTitle in $tabsByWindow[$tabWindowHandle]) { $refusedTabs.Add($tabTitle) }
				}
				continue
			}

			# Owning the window means owning everything in it. Otherwise only the recorded tabs go,
			# which is what leaves a shared terminal window's other tabs untouched.
			$targetTitles = if ($ownsWholeWindow) {
				@($liveTabTitles)
			}
			else {
				@($tabsByWindow[$tabWindowHandle])
			}

			foreach ($tabTitle in $targetTitles) {
				# The tab this command runs in cannot close itself mid-run. Remember it and let the
				# process-exit seam close it once everything else is done.
				if ($hostingTerminal -and
					$hostingTerminal.Handle -eq $terminalHandle -and
					$hostingTerminal.TabTitle -eq $tabTitle) {
					$ownTabRecord = $tabTitle
					$ownTabTerminalHandle = [int64]$tabWindowHandle
					Write-LogDebug "  Deferring this shell's own tab => [$tabTitle]" -Style Step
					continue
				}

				if ($liveTabTitles -notcontains $tabTitle) {
					$alreadyGoneCount++
					Write-LogDebug "  Already closed => [$tabTitle]" -Style Step
					continue
				}

				if (-not $PSCmdlet.ShouldProcess("terminal tab [$tabTitle]", "Close")) { continue }

				Write-LogDebug "  Closing terminal tab => [$tabTitle]" -Style Step

				if (Close-WindowsTerminalTab -WindowHandle $terminalHandle -TabTitle $tabTitle) {
					$closedTabs.Add($tabTitle)
					# Let Windows Terminal remove the tab from the strip before the next close.
					Start-Sleep -Milliseconds 25
				}
				else {
					$refusedTabs.Add($tabTitle)
				}
			}
		}
	}

	# Last word on owned terminal windows: any that the tab pass did not take down is asked to close
	# directly. Windows Terminal may confirm first, which is the same graceful treatment every other
	# window gets here - and far better than leaving the workspace's terminal running with nothing
	# left to close it. Liveness is re-read rather than taken from the pre-teardown snapshot, so a
	# window the tab pass already emptied is not messaged again.
	if ($ownedTerminalWindows.Count -gt 0) {
		if (Get-Command Clear-WindowCache -ErrorAction SilentlyContinue) { Clear-WindowCache }
		$terminalsAfterTabPass = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue)

		foreach ($ownedTerminal in $ownedTerminalWindows) {
			# The window hosting the deferred tab is excluded: the exit seam closes that tab and the
			# window goes with it, so messaging it here would race the tracker write.
			if ($null -ne $ownTabTerminalHandle -and $ownTabTerminalHandle -eq $ownedTerminal.Handle) { continue }

			$survivor = @($terminalsAfterTabPass | Where-Object { [int64]$_.Handle -eq $ownedTerminal.Handle })[0]
			if (-not $survivor) { continue }

			if (-not $PSCmdlet.ShouldProcess("Windows Terminal window [$($survivor.Title)]", "Close")) { continue }

			Write-LogDebug "  Closing terminal window => [$($survivor.Title)]" -Style Step
			[void][CloseWorkspaceWin32]::PostMessage([IntPtr]$ownedTerminal.Handle, [CloseWorkspaceWin32]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)

			$postedWindows.Add([PSCustomObject]@{
					Workspace = $ownedTerminal.Workspace
					Handle    = $ownedTerminal.Handle
					Title     = [string]$survivor.Title
				})
		}
	}

	# Put the view back before the desktop sweep, so the sweep never runs with the user standing on a
	# desktop that is about to be removed.
	if ($null -ne $restoreDesktopIndex) {
		[void](Ensure-DesktopVisible -DesktopIndex $restoreDesktopIndex)
	}

	# WM_CLOSE is posted, not sent, and an application may put up a save prompt - poll instead of
	# assuming, so the report below distinguishes "closed" from "refused" and so the empty-desktop
	# sweep does not run while windows are still on their way out.
	$refusedWindows = @(Wait-WindowsClosed -Window $postedWindows)

	foreach ($refusedWindow in $refusedWindows) {
		Write-LogWarning "Window [$($refusedWindow.Title)] did not close - leaving it alone (it may be waiting on unsaved work)." -NoLeadingNewline
	}

	$closedWindowCount = $postedWindows.Count - $refusedWindows.Count

	$selectedLabel = $selectedWorkspaces -join ', '
	$attemptedAnything = $postedWindows.Count -gt 0 -or $closedTabs.Count -gt 0 -or $refusedTabs.Count -gt 0

	if ($closedWindowCount -gt 0 -or $closedTabs.Count -gt 0) {
		Write-LogSuccess "Closed $closedWindowCount window(s) and $($closedTabs.Count) terminal tab(s) for [$selectedLabel]!"
	}
	elseif (-not $attemptedAnything -and -not $WhatIfPreference) {
		# Nothing was even attempted: every tracked item had already gone, or was held back for a
		# workspace that stays open. A success of zero would read as a teardown that found nothing to
		# do, and the refusal warnings above already cover the case where something resisted.
		Write-LogWarning "Nothing was left to close for [$selectedLabel]!"
	}

	$notes = @()
	if ($alreadyGoneCount -gt 0) { $notes += "$alreadyGoneCount tracked item(s) were already closed" }
	if ($skippedWindows.Count -gt 0) { $notes += "$($skippedWindows.Count) window(s) kept for a workspace that stays open => $($skippedWindows -join ', ')" }
	if ($refusedTabs.Count -gt 0) { $notes += "$($refusedTabs.Count) terminal tab(s) refused to close => $($refusedTabs -join ', ')" }
	if ($notes.Count -gt 0) { Write-LogList -Items $notes }

	# Last, once everything the workspace held has actually gone: the desktops go too. A workspace's
	# desktops are as much part of it as its windows, so leaving them behind leaves the session one
	# workspace wider on every open/close cycle.
	#
	# Named explicitly rather than swept with -EmptyOnly, because the one window a teardown cannot
	# close before this point is the shell it is running in - and when the workspace opened that shell
	# (the -Alongside flow does), its desktop is never empty at sweep time and no later run would ever
	# tidy it. Removing the desktop relocates that window instead of stranding it. -EmptyOnly still
	# runs afterwards, as the net for desktops this workspace emptied without ever having recorded a
	# window on them.
	# Nothing has to be re-mapped afterwards: no desktop index is ever stored, so a shifted index
	# cannot be believed later. The next teardown resolves its desktops from window handles again.
	if ($closingDesktops.Count -gt 0) {
		if ($PSCmdlet.ShouldProcess("virtual desktop(s) $((@($closingDesktops | Sort-Object)) -join ', ')", "Remove")) {
			[void](Remove-VirtualDesktops -Index @($closingDesktops))
		}
	}

	# The net: desktops this workspace emptied but never had a window on at teardown time, so the pass
	# above could not name them. Its return value is suppressed the way Kill-All does it - a failed
	# sweep owns its own output and must not leak a bare $false.
	if ($PSCmdlet.ShouldProcess("emptied virtual desktops", "Remove")) {
		[void](Remove-VirtualDesktops -EmptyOnly)
	}

	# Written before the exit seam below, because that ends the process outright. Entries whose windows
	# were already gone are dropped too: the tracker describes what is open, and they no longer are.
	if ($PSCmdlet.ShouldProcess($state.Path, "Update the open-workspace tracker")) {
		$saveParams = @{ Entry = $survivingEntries }
		if (-not [string]::IsNullOrWhiteSpace($StatePath)) { $saveParams['StatePath'] = $StatePath }
		Save-WorkspaceState @saveParams
	}

	if ($ownTabRecord) {
		if ($PSCmdlet.ShouldProcess("this shell's own terminal tab [$ownTabRecord]", "Close")) {
			# Exits this process, which closes the tab. Nothing after this line runs, which is why
			# the tracker was written above.
			Invoke-TerminateWindowsTerminalTabsExit
			return
		}
	}

	# Checked directly rather than through ShouldProcess: focus is the one thing here worth doing
	# silently, and routing it through a gate would add a "What if" line for what is otherwise a
	# no-op in the tab the command was typed in.
	if (-not $WhatIfPreference) {
		Focus-TerminalTab
	}
}
