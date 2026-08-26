function Get-WorkspaceOpenDelta {
	<#
	.SYNOPSIS
		Builds the tracker entry for one workspace open: the windows and terminal tabs it produced.

	.DESCRIPTION
		The ownership rule for Close-Workspace, in one place. Given the window handles and the
		Windows Terminal tab snapshot taken before an Open-Workspace invocation ran its actions,
		this enumerates what exists now and returns the difference as a single tracker entry.

		Windows are differenced by handle. Anything on screen whose handle was not there before
		belongs to this open; anything that was already there does not, which is exactly what keeps
		a single-instance app out of a later workspace's entry. Obsidian launched by workspace A is
		already running when workspace B opens, so B's Open-Obsidian action creates no window, so
		Obsidian never appears in B's delta and closing B leaves it alone.

		Terminal tabs cannot be differenced by handle - they are not top-level windows - so they are
		differenced per Windows Terminal window by title, by COUNT rather than by set membership. A
		second tab titled "MyProject.Api" opened next to an existing one is a new tab even though
		the title was already present; set subtraction would miss it.

		Both process id and window title are recorded alongside the handle. Handles are the only
		unambiguous key while a window lives, but Electron apps recreate their window (new handle,
		same process) and a restarted app keeps neither - the extra fields let Close-Workspace
		re-resolve a record whose handle has gone stale.

	.PARAMETER Workspace
		Name of the workspace this entry belongs to.

	.PARAMETER ExistingWindowHandles
		Window handles that existed before the open. Accepts a HashSet[IntPtr] (what Open-Workspace
		already builds for its layout pass), raw handle values, or window objects exposing .Handle,
		so callers do not have to reshape what they already have.

	.PARAMETER ExistingTerminalTabs
		The Get-TerminalTabSnapshot taken before the open (window handle -> tab titles). Omit when
		terminal tabs are not of interest; every tab currently open then counts as new.

	.PARAMETER PreCapturedTerminalTabs
		The AFTER snapshot, taken by the caller while the terminal was still on the visible desktop -
		Open-Workspace takes it right before its layout action parks the terminal on one of the
		workspace's own desktops. Supply it to spare this function the desktop round trip described
		below; omit it and the snapshot is read here instead, with -EnsureVisible.

	.PARAMETER DesktopOffset
		Desktop offset this open used (0 normally, +N for -Alongside). Recorded for context.

	.PARAMETER Alongside
		Present when the workspace was opened alongside existing desktops. Recorded for context.

	.PARAMETER AdoptUnclaimed
		Also claim what was already on screen, not only what this open created.

		A plain open resets the virtual desktops, so when it finishes only this workspace is on
		screen - which makes the windows there this workspace's. That is what lets it claim an app
		that was ALREADY RUNNING when it started: Open-ClaudeDesktop reporting "Claude is already
		running" creates no window, so a pure diff records nothing and Close-Workspace cannot touch
		it. Worse, that state is self-perpetuating - the app escapes one teardown, is therefore
		already running at the next open, is never recorded again, and becomes permanently
		unclosable. Adoption breaks that cycle.

		Adoption reaches only for what Universal.VisibleWindowExclusions does not name. That is the
		same list Kill-All uses to decide what a blunt teardown must leave alone (Rainmeter,
		WindowsTerminal, Docker Desktop, PowerToys, ...), and it means exactly what is wanted here:
		these processes are never a workspace's to close simply because they happened to be running
		while it opened. The exclusion applies to adoption only - a window this open genuinely
		created is always recorded, whatever its process is called, because the diff already proves
		it belongs to this workspace.

		Never use adoption for an -Alongside open, which adds to a screen other workspaces are
		already using: there it must claim only what it actually created, or it steals their
		windows. For the same reason only the FIRST workspace of a multi-workspace plain run should
		adopt; the rest are additions to the session it just defined.

	.PARAMETER ProtectedWindowHandles
		Live window handles belonging to alongside workspaces this plain open preserves (from
		Get-WorkspaceOpenProtection). Adoption never claims them - neither the windows nor, for a
		protected terminal window, its tabs. Windows the diff proves this open created are always
		recorded regardless. Accepts the same shapes as ExistingWindowHandles.

	.OUTPUTS
		[ordered] one tracker entry: Workspace, Alongside, DesktopOffset, OpenedUtc, ShellPid,
		Windows, TerminalTabs.

		Which virtual desktops the workspace occupies is deliberately NOT recorded here. Desktop
		indexes shift whenever a desktop to their left is removed, so a stored index goes stale and
		acting on a stale one would reach onto another workspace's desktop. Close-Workspace derives the
		set live instead, from where this entry's windows actually are at teardown time.

	.EXAMPLE
		$entry = Get-WorkspaceOpenDelta -Workspace 'Server' -ExistingWindowHandles $before -ExistingTerminalTabs $tabsBefore
		$entry.Windows.Count
	#>
	[CmdletBinding()]
	[OutputType([System.Collections.Specialized.OrderedDictionary])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Workspace,

		[Parameter()]
		[object]$ExistingWindowHandles,

		[Parameter()]
		[hashtable]$ExistingTerminalTabs,

		[Parameter()]
		[hashtable]$PreCapturedTerminalTabs,

		[Parameter()]
		[int]$DesktopOffset = 0,

		[Parameter()]
		[switch]$Alongside,

		[Parameter()]
		[switch]$AdoptUnclaimed,

		[Parameter()]
		[object]$ProtectedWindowHandles
	)

	# Handles reach this function as IntPtr, as window objects, or as plain numbers depending on
	# the caller; normalise everything to Int64 so the set comparison below cannot miss a match
	# purely because two callers spelled the same handle differently.
	$toHandleValue = {
		param($Value)

		if ($null -eq $Value) { return $null }
		if ($Value -is [IntPtr]) { return $Value.ToInt64() }
		if ($Value.PSObject.Properties['Handle']) { return (& $toHandleValue $Value.Handle) }

		try { return [int64]$Value } catch { return $null }
	}

	$existingHandles = New-Object 'System.Collections.Generic.HashSet[int64]'
	foreach ($existing in @($ExistingWindowHandles)) {
		$handleValue = & $toHandleValue $existing
		if ($null -ne $handleValue) {
			[void]$existingHandles.Add($handleValue)
		}
	}

	# Windows a plain open must preserve (they belong to a live alongside workspace). Same
	# normalisation as the existing set: whatever shape the caller has, the comparison below
	# happens in int64.
	$protectedHandles = New-Object 'System.Collections.Generic.HashSet[int64]'
	foreach ($protected in @($ProtectedWindowHandles)) {
		$handleValue = & $toHandleValue $protected
		if ($null -ne $handleValue) {
			[void]$protectedHandles.Add($handleValue)
		}
	}

	# The processes adoption must not reach for. Read from configuration rather than hard-coded so
	# there is one answer in the repository to "which windows does a teardown leave alone", the
	# same one Terminate-AllProcessesWithVisibleWindows uses. Matched on the exact process name,
	# case-insensitively, exactly as that function does.
	$adoptionExclusions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	if ($AdoptUnclaimed -and $Configuration -and $Configuration.Universal -and $Configuration.Universal.VisibleWindowExclusions) {
		foreach ($exclusion in @($Configuration.Universal.VisibleWindowExclusions)) {
			if (-not [string]::IsNullOrWhiteSpace($exclusion)) { [void]$adoptionExclusions.Add([string]$exclusion) }
		}
	}

	$openedWindows = [System.Collections.Generic.List[object]]::new()
	foreach ($window in @(Get-WindowHandle -ErrorAction SilentlyContinue)) {
		if (-not $window) { continue }

		$handleValue = & $toHandleValue $window.Handle
		if ($null -eq $handleValue -or $handleValue -eq 0) { continue }

		# Already there before the open, so only adoption can claim it - and only when its process
		# is not one of the ones a teardown always leaves alone, and never when it belongs to a
		# preserved alongside workspace. The protection guard sits on the adoption branch ONLY:
		# a window the diff proves this open created is always recorded, whatever set it is in.
		if ($existingHandles.Contains($handleValue)) {
			if (-not $AdoptUnclaimed) { continue }
			if ($adoptionExclusions.Contains([string]$window.ProcessName)) { continue }
			if ($protectedHandles.Contains($handleValue)) { continue }
		}

		$processId = 0
		if ($null -ne $window.ProcessId) {
			try { $processId = [int64]$window.ProcessId } catch { $processId = 0 }
		}

		$openedWindows.Add([ordered]@{
				Handle      = $handleValue
				ProcessId   = $processId
				ProcessName = [string]$window.ProcessName
				Title       = [string]$window.Title
			})
	}

	# Every window a tab snapshot describes is a Windows Terminal window, so one exclusion check
	# settles whether adoption may claim pre-existing tabs at all. With WindowsTerminal on the
	# exclusion list (the shipped default) a plain open records only the tabs it actually created,
	# which is what stops it from claiming a tab left over from unrelated work.
	$adoptTerminalTabs = [bool]$AdoptUnclaimed -and -not $adoptionExclusions.Contains('WindowsTerminal')

	# Both snapshots are keyed by window handle, and a hashtable lookup is TYPE-exact: an Int32 key
	# never matches an Int64 one, however equal the numbers look. Get-TerminalTabSnapshot keys by
	# Int64, so a caller that built its pre-open map with plain integer literals would match nothing,
	# every tab on screen would look newly created, and an adopting open would claim tabs it never
	# opened. Normalise the incoming keys once so the comparison cannot be defeated that way.
	$existingTabsByWindow = @{}
	if ($ExistingTerminalTabs) {
		foreach ($existingKey in @($ExistingTerminalTabs.Keys)) {
			try { $existingTabsByWindow[[int64]$existingKey] = @($ExistingTerminalTabs[$existingKey]) }
			catch { continue }
		}
	}

	$openedTabs = [System.Collections.Generic.List[object]]::new()
	# Prefer the snapshot the caller already took while the terminal was still on the visible
	# desktop. Reading it HERE is the expensive path: this runs at the END of an open, by which
	# point the layout pass has parked the workspace's terminal on one of the workspace's own
	# desktops, and Windows Terminal exposes no tab strip while its desktop is off screen - so the
	# read costs a desktop round trip, which the user sees as the view jumping to the terminal and
	# back AFTER the workspace's final Focus-VirtualDesktop landing. Open-Workspace therefore
	# captures the snapshot just before its layout action moves the terminal and passes it in.
	#
	# The -EnsureVisible read stays as the fallback for callers with no earlier capture: without it
	# the terminal is read as having no tabs and the workspace's own tabs are never recorded. An
	# explicitly supplied but EMPTY snapshot is honoured rather than re-read - it means the caller
	# looked and found nothing readable, and re-reading would pay for the round trip this avoids.
	$currentTerminalTabs = if ($null -ne $PreCapturedTerminalTabs) {
		$PreCapturedTerminalTabs
	}
	else {
		Get-TerminalTabSnapshot -EnsureVisible
	}

	foreach ($windowHandle in @($currentTerminalTabs.Keys)) {
		$windowHandleValue = [int64]$windowHandle

		# A preserved workspace's terminal window is never adoptable, tabs included - even when
		# WindowsTerminal is missing from VisibleWindowExclusions. Adoption-only, like the
		# window guard above: tabs this open genuinely added to such a window still diff in.
		if ($adoptTerminalTabs -and $protectedHandles.Contains($windowHandleValue)) { continue }

		# Consume one prior occurrence per matching title: whatever is left over after the existing
		# tabs have been accounted for is what this open added. Adopting skips that accounting
		# entirely, so every tab on screen counts as this workspace's - the tab equivalent of the
		# already-running app the window pass adopts above.
		$unclaimed = [System.Collections.Generic.List[string]]::new()
		if (-not $adoptTerminalTabs -and $existingTabsByWindow.ContainsKey($windowHandleValue)) {
			foreach ($existingTitle in @($existingTabsByWindow[$windowHandleValue])) {
				$unclaimed.Add([string]$existingTitle)
			}
		}

		foreach ($currentTitle in @($currentTerminalTabs[$windowHandle])) {
			$title = [string]$currentTitle
			if ($unclaimed.Remove($title)) { continue }

			$openedTabs.Add([ordered]@{
					WindowHandle = $windowHandleValue
					Title        = $title
				})
		}
	}

	return [ordered]@{
		Workspace     = $Workspace
		Alongside     = [bool]$Alongside
		DesktopOffset = [int]$DesktopOffset
		OpenedUtc     = ([DateTimeOffset]::UtcNow).ToString('o')
		ShellPid      = [int]$PID
		Windows       = $openedWindows.ToArray()
		TerminalTabs  = $openedTabs.ToArray()
	}
}
