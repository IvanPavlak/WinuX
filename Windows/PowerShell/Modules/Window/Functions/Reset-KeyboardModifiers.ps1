function Reset-KeyboardModifiers {
	<#
	.SYNOPSIS
		Releases modifier keys (Shift, Ctrl, Alt, Win) left logically stuck in the session.

	.DESCRIPTION
		Workspace orchestration positions windows with synthesized keyboard input
		(Win+Arrow snaps, FancyZones layout shortcuts, Shift-drag snapping). If such a
		sequence is interrupted between a key-down and its key-up - the hosting shell is
		closed mid-sequence, the process is killed, an injection is partially blocked -
		the modifier stays LOGICALLY held for the entire desktop session: typed letters
		come out as if Caps Lock were stuck (held Shift), Enter stops submitting commands
		(Shift+Enter inserts a line in PSReadLine), or keystrokes fire shortcuts (held
		Win). Previously only signing out and back in reset this state.

		This function performs the same reset in place: it reads the async key state of
		every modifier variant (left/right/neutral Shift, Ctrl, Alt, and both Win keys)
		and injects a matching key-up for each one still reported as held. Keys that are
		not held are never touched, and toggle keys (Caps Lock, Num Lock) are never sent,
		so on a quiescent keyboard this is a read-only no-op.

		The workspace engine calls this automatically at snap, retry, and rerun
		checkpoints, so a stuck modifier self-heals during orchestration. Run it manually
		whenever typing suddenly behaves as if a modifier were held down. If a stuck
		Shift prevents submitting the command (Enter inserts a line instead), first tap
		both Shift keys - a physical press+release also clears the injected state - then
		run this to clear any remaining variants.

	.PARAMETER IncludeMouseButton
		Also releases the left mouse button when the session reports it as held. An
		interrupted Shift-drag snap strands the button in the pressed state, which blocks
		clicks and window drags. Off by default so a physically held button is never
		interrupted; orchestration failure paths enable it.

	.EXAMPLE
		Reset-KeyboardModifiers
		# Releases any stuck Shift/Ctrl/Alt/Win keys and reports which were released

	.EXAMPLE
		Reset-KeyboardModifiers -IncludeMouseButton
		# Additionally releases a stuck left mouse button (post-failure cleanup)

	.OUTPUTS
		System.String[] - names of the key(s) that were released; empty when none were stuck.
	#>
	[CmdletBinding()]
	[OutputType([string[]])]
	param (
		[Parameter()]
		[switch]$IncludeMouseButton
	)

	if (-not ([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
		Write-LogWarning "WindowModule.Native is not loaded - cannot reset keyboard modifier state."
		return [string[]]@()
	}

	$released = [string[]]@([WindowModule.Native]::ReleaseModifierKeys([bool]$IncludeMouseButton))

	if ($released.Count -gt 0) {
		Write-LogWarning "Released stuck modifier key(s) => [$($released -join ', ')]"
	}
	elseif (Test-LogVerbose) {
		Write-LogDebug " No stuck modifier keys detected" -Style Success
	}

	return $released
}
