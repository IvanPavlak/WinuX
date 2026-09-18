function Focus-VirtualDesktop {
	<#
	.SYNOPSIS
		Switches to a virtual desktop and locks keyboard focus onto a window living there.

	.DESCRIPTION
		Reliably lands the user on a specific virtual desktop after a workspace run.

		Workspace setup (Set-WorkspaceWindowLayout / Snap-AllWindows) hops across every
		virtual desktop to move and snap windows, then ends with a switch back to the first
		desktop and a `Focus-TerminalTab`. Two things make that final landing unreliable:

		  1. A desktop switch is asynchronous, and in a long-running shell the VirtualDesktop
		     COM/RPC session can go stale and the switch silently no-ops (the exact failure
		     mode Reset-VirtualDesktopState exists to recover), leaving the previous desktop
		     visible unless the switch is confirmed and recovered.
		  2. Even when the switch takes, nothing guarantees a foreground window on the
		     target desktop. A virtual-desktop switch only "sticks" when focus lands on a
		     window that lives there; otherwise focus can revert to whatever window was
		     last activated on another desktop (a browser/app snapped on a higher desktop),
		     pulling the visible desktop back with it.

		This function closes both gaps with the Window module's own verbs:

		  - Switch-VirtualDesktop, which switches, confirms the desktop is showing, retries,
		    falls back to a Reset-VirtualDesktopState session reset and clears the window cache
		    (the same call Snap-AllWindows and Ensure-DesktopVisible make). No VirtualDesktop
		    cmdlet is called here and no retry or recovery block is hand-rolled.
		  - ForceForegroundWindow (from WindowNative.cs) to lock focus onto a real window on
		    the target desktop, preferring Windows Terminal via Focus-TerminalTab - handed the
		    handle of the terminal verified to live there - so the terminal/output stays
		    visible after the run.

	.PARAMETER DesktopNumber
		The 1-based desktop number to focus (matching layout-file convention). Default is 1
		(the first virtual desktop).

	.PARAMETER DesktopOffset
		Workspace desktop offset (number of pre-existing desktops to the left), used by
		"alongside" workspaces. Default 0. Converted together with DesktopNumber via
		ConvertTo-InternalDesktopIndex.

	.OUTPUTS
		None. Writes a status message to the console indicating which desktop was focused.

	.EXAMPLE
		Focus-VirtualDesktop
		# Switches to and focuses the first virtual desktop.

	.EXAMPLE
		Focus-VirtualDesktop -DesktopNumber 1 -DesktopOffset 2
		# Focuses the first desktop of an alongside workspace that starts after two existing desktops.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[int]$DesktopNumber = 1,

		[Parameter()]
		[int]$DesktopOffset = 0
	)

	if (-not (Import-VirtualDesktopModule -Silent)) {
		Write-LogWarning "VirtualDesktop module unavailable - cannot focus Virtual Desktop $DesktopNumber!"
		return
	}

	$targetIndex = ConvertTo-InternalDesktopIndex -DesktopNumber $DesktopNumber -DesktopOffset $DesktopOffset

	Write-LogTitle "Focusing Virtual Desktop $DesktopNumber"
	Write-LogDebug "  Target desktop index => [$targetIndex]"

	# Switch-VirtualDesktop confirms the switch, retries, recovers a stale COM session once, and
	# clears the window cache so the lookups below never act on the previous desktop's handles.
	$desktopSwitched = $false
	try {
		$desktopSwitched = [bool](Switch-VirtualDesktop -Index $targetIndex)
	}
	catch {
		Write-LogDebug "  Switch to desktop index $targetIndex failed => $($_.Exception.Message)" -Style Error
	}

	if (-not $desktopSwitched) {
		Write-LogError "Failed to focus Virtual Desktop $DesktopNumber after retries!"
		return
	}

	# Resolve which visible top-level windows actually live on the target desktop so we can
	# park keyboard focus on one of them - this is what makes the switch "stick".
	$windowsOnTarget = @()
	$terminalOnTarget = $null

	$candidateWindows = @(Get-WindowHandle -ErrorAction SilentlyContinue)

	# Only ONE focus target is ever used below, so resolving the desktop of EVERY window
	# (two COM roundtrips each) wasted 0.2-0.6s at the end of every open. Check terminal
	# windows first (they are the preferred target), then everything else, and stop at
	# the first window that lives on the target desktop.
	$orderedCandidates = @($candidateWindows | Where-Object { $_.ProcessName -eq 'WindowsTerminal' }) +
	@($candidateWindows | Where-Object { $_.ProcessName -ne 'WindowsTerminal' })

	foreach ($win in $orderedCandidates) {
		# -1 means the window closed between enumeration and lookup, or has no desktop - skip it.
		if ((Get-WindowDesktopIndex -WindowHandle $win.Handle) -ne $targetIndex) { continue }
		$windowsOnTarget += $win
		if ($win.ProcessName -eq 'WindowsTerminal') {
			$terminalOnTarget = $win
		}
		break
	}

	# Prefer the terminal (keeps post-run output visible); fall back to any window on the
	# target desktop. Focus-TerminalTab is only safe when the terminal is on this desktop -
	# activating a terminal that lives elsewhere would drag the view off the target desktop -
	# which is why the verified HANDLE goes with the call. Left to itself Focus-TerminalTab
	# activates the first WindowsTerminal PROCESS, and one process hosts every one of its
	# windows, so the check above could clear one window while a sibling on another desktop
	# is the one that actually comes forward.
	$focusedTitle = $null
	if ($terminalOnTarget -and (Get-Command Focus-TerminalTab -ErrorAction SilentlyContinue)) {
		try {
			Focus-TerminalTab -WindowHandle $terminalOnTarget.Handle -Quiet
		}
		catch {
			[void][WindowModule.Native]::ForceForegroundWindow($terminalOnTarget.Handle)
		}
		$focusedTitle = "Windows Terminal"
	}
	elseif ($windowsOnTarget.Count -gt 0) {
		$focusTarget = $windowsOnTarget | Select-Object -First 1
		[void][WindowModule.Native]::ForceForegroundWindow($focusTarget.Handle)
		$focusedTitle = $focusTarget.Title
	}

	if ($focusedTitle) {
		Write-LogDebug " Locked focus onto => [$focusedTitle]" -Style Step
		Write-LogSuccess "Focused Virtual Desktop $DesktopNumber!"
	}
	else {
		Write-LogWarning "Switched to Virtual Desktop $DesktopNumber, but found no window to focus!"
	}

	return
}
