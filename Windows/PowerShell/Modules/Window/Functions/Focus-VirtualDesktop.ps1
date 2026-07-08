function Focus-VirtualDesktop {
	<#
	.SYNOPSIS
		Switches to a virtual desktop and locks keyboard focus onto a window living there.

	.DESCRIPTION
		Reliably lands the user on a specific virtual desktop after a workspace run.

		Workspace setup (Set-WorkspaceWindowLayout / Snap-AllWindows) hops across every
		virtual desktop to move and snap windows, then ends with a single, unverified
		`Switch-Desktop -Desktop 0` and a `Focus-TerminalTab`. Two things make that final
		landing unreliable:

		  1. The trailing Switch-Desktop has no Wait-DesktopSwitch confirmation and no
		     module-reset fallback. In a long-running shell the VirtualDesktop COM/RPC
		     session can go stale and the switch silently no-ops (the exact failure mode
		     Reset-VirtualDesktopState exists to recover), leaving the previous desktop
		     visible.
		  2. Even when the switch takes, nothing guarantees a foreground window on the
		     target desktop. A virtual-desktop switch only "sticks" when focus lands on a
		     window that lives there; otherwise focus can revert to whatever window was
		     last activated on another desktop (a browser/app snapped on a higher desktop),
		     pulling the visible desktop back with it.

		This function closes both gaps using logic already proven elsewhere in the module:

		  - The Switch-Desktop + Wait-DesktopSwitch retry loop with a Reset-VirtualDesktopState
		    recovery pass (mirrors Snap-AllWindows' desktop-switch block).
		  - ForceForegroundWindow (from WindowNative.cs) to lock focus onto a real window on
		    the target desktop, preferring Windows Terminal via Focus-TerminalTab so the
		    terminal/output stays visible after the run.

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

	if (-not (Get-Command Switch-Desktop -ErrorAction SilentlyContinue)) {
		if (Get-Command Import-VirtualDesktopModule -ErrorAction SilentlyContinue) {
			[void](Import-VirtualDesktopModule -Silent)
		}
	}

	if (-not (Get-Command Switch-Desktop -ErrorAction SilentlyContinue)) {
		Write-LogWarning "VirtualDesktop module unavailable - cannot focus Virtual Desktop $DesktopNumber!"
		return
	}

	$targetIndex = ConvertTo-InternalDesktopIndex -DesktopNumber $DesktopNumber -DesktopOffset $DesktopOffset

	Write-LogTitle "Focusing Virtual Desktop $DesktopNumber"
	Write-LogDebug "  Target desktop index => [$targetIndex]"

	# Robust switch - confirm via Wait-DesktopSwitch and recover stale COM state with a
	# VirtualDesktop module reset. Mirrors the proven block in Snap-AllWindows.
	$desktopSwitched = $false
	$maxDesktopSwitchRetries = 3
	for ($attempt = 1; $attempt -le $maxDesktopSwitchRetries; $attempt++) {
		try {
			$null = Switch-Desktop -Desktop $targetIndex -ErrorAction Stop
			if (Wait-DesktopSwitch -TargetDesktopIndex $targetIndex) {
				$desktopSwitched = $true
				break
			}
		}
		catch {
			Write-LogDebug "  Failed to switch to desktop index $targetIndex (attempt $attempt/$maxDesktopSwitchRetries): $_" -Style Warning
		}
	}

	if (-not $desktopSwitched) {
		$moduleReloaded = Reset-VirtualDesktopState
		if ($moduleReloaded) {
			try {
				$null = Switch-Desktop -Desktop $targetIndex -ErrorAction Stop
				$desktopSwitched = Wait-DesktopSwitch -TargetDesktopIndex $targetIndex
			}
			catch {
				$desktopSwitched = $false
			}
		}

		if (Test-LogVerbose) {
			if ($desktopSwitched) {
				Write-LogDebug "  Desktop index $targetIndex recovered after VirtualDesktop module reset" -Style Warning
			}
			else {
				Write-LogDebug "  Unable to switch to desktop index $targetIndex after retries" -Style Error
			}
		}
	}

	if (-not $desktopSwitched) {
		Write-LogError "Failed to focus Virtual Desktop $DesktopNumber after retries!"
		return
	}

	# Refresh the window snapshot after the transition so we don't act on stale handles.
	if (Get-Command Clear-WindowCache -ErrorAction SilentlyContinue) {
		Clear-WindowCache
	}

	# Resolve which visible top-level windows actually live on the target desktop so we can
	# park keyboard focus on one of them - this is what makes the switch "stick".
	$windowsOnTarget = @()
	$terminalOnTarget = $null
	$desktopLookupAvailable = (Get-Command Get-DesktopFromWindow -ErrorAction SilentlyContinue) -and
	(Get-Command Get-DesktopIndex -ErrorAction SilentlyContinue)

	if ($desktopLookupAvailable) {
		$candidateWindows = Get-WindowHandle -ErrorAction SilentlyContinue
		foreach ($win in $candidateWindows) {
			try {
				$winDesktop = Get-DesktopFromWindow -Hwnd $win.Handle
				if (-not $winDesktop) { continue }
				if ((Get-DesktopIndex -Desktop $winDesktop) -eq $targetIndex) {
					$windowsOnTarget += $win
					if (-not $terminalOnTarget -and $win.ProcessName -eq 'WindowsTerminal') {
						$terminalOnTarget = $win
					}
				}
			}
			catch {
				# Window may have closed between enumeration and lookup - skip it.
			}
		}
	}

	# Prefer the terminal (keeps post-run output visible); fall back to any window on the
	# target desktop. Focus-TerminalTab is only safe when the terminal is on this desktop -
	# activating a terminal that lives elsewhere would drag the view off the target desktop.
	$focusedTitle = $null
	if ($terminalOnTarget -and (Get-Command Focus-TerminalTab -ErrorAction SilentlyContinue)) {
		try {
			Focus-TerminalTab -Quiet
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
