function Reset-Windows {
	<#
	.SYNOPSIS
		Resets the window layout to a clean slate for layout testing.

	.DESCRIPTION
		Convenience wrapper used when testing layout behavior. Runs three steps
		in order:
		  1. Remove-VirtualDesktops  - collapse down to a single virtual desktop
		  2. Move-Windows            - move every window to the target virtual
		                               desktop (and, optionally, a target monitor)
		  3. Center-Windows          - center every window on the target monitor
		                               (or on its current monitor when no monitor
		                               is configured)

		The configured monitor is passed on to Center-Windows rather than letting it
		re-derive a monitor per window. Because Center-Windows runs last, that makes
		the reset self-correcting: a window that something else moved to another
		monitor during the run - notably FancyZones restoring a remembered zone after
		the virtual desktops collapse - is pulled back to the configured monitor
		instead of being centered wherever it drifted to.

		A failed Remove-VirtualDesktops is surfaced as a warning instead of being
		ignored, since it changes how much work the move pass has to do.

		This reproduces the manual sequence:
		  PC      => Remove-VirtualDesktops; Move-Windows -Monitor 2 -VirtualDesktop 1; Center-Windows
		  Laptop/ => Remove-VirtualDesktops; Move-Windows -VirtualDesktop 1; Center-Windows
		  Work

		Defaults for -VirtualDesktop and -Monitor are read per machine from
		$global:Configuration.ResetAllWindowsDefaults, keyed by the machine type
		Get-LayoutMachineType resolves - the same one the window layouts themselves
		are read under, so a LayoutMachineTypeOverrides entry (or a small primary
		display) selects the matching reset profile as well. That keeps a machine
		running on a borrowed monitor setup from consolidating windows onto a monitor
		it no longer has. On the PC, windows are consolidated onto monitor 2; on the
		laptop and work machines no monitor targeting is applied. Explicitly passing
		-VirtualDesktop or -Monitor overrides the configured default for that run.

	.PARAMETER VirtualDesktop
		The 1-based virtual desktop to consolidate all windows onto.
		When omitted, the per-machine default from ResetAllWindowsDefaults is used.

	.PARAMETER Monitor
		The physical monitor to move all windows to. Accepts a 1-based index
		("2"), a label ("Primary", "Secondary", "Monitor3"), or a device name
		("\\.\DISPLAY1"). Pass an empty string to skip monitor targeting.
		When omitted, the per-machine default from ResetAllWindowsDefaults is used.

	.EXAMPLE
		Reset-Windows
		Uses the current machine's configured defaults (e.g. monitor 2 + desktop 1
		on the PC, desktop 1 with no monitor targeting on laptop/work).

	.EXAMPLE
		Reset-Windows -VirtualDesktop 2 -Monitor Primary
		Overrides the defaults: consolidate onto virtual desktop 2 and monitor Primary.

	.EXAMPLE
		Reset-Windows -Monitor ""
		Skip monitor targeting for this run, keeping the configured virtual desktop.
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[ValidateRange(1, 100)]
		[int]$VirtualDesktop,

		[Parameter()]
		[string]$Monitor
	)

	Write-LogTitle "Resetting All Windows"

	# The defaults are display-shaped - "consolidate onto monitor 2" is a statement about a monitor
	# setup, not about a machine's identity - so they follow the SAME switch as the window layouts
	# (Get-LayoutMachineType): a LayoutMachineTypeOverrides entry, else SmallDisplayMachineType on a
	# laptop-class display, else the detected machine type. A machine temporarily on another setup
	# therefore resets FOR that setup instead of aiming windows at a monitor that is not attached.
	$machineType = Get-LayoutMachineType

	$defaults = $null
	if ($global:Configuration -and $global:Configuration.ResetAllWindowsDefaults) {
		$defaults = $global:Configuration.ResetAllWindowsDefaults[$machineType]
		if (-not $defaults) {
			$defaults = $global:Configuration.ResetAllWindowsDefaults["Default"]
		}
	}
	if (-not $defaults) {
		$defaults = @{ VirtualDesktop = 1; Monitor = "" }
	}

	if (-not $PSBoundParameters.ContainsKey('VirtualDesktop')) {
		$VirtualDesktop = [int]$defaults.VirtualDesktop
	}
	if (-not $PSBoundParameters.ContainsKey('Monitor')) {
		$Monitor = [string]$defaults.Monitor
	}

	if (Test-LogVerbose) {
		$monitorText = if ($Monitor) { $Monitor } else { "(current)" }
		Write-LogDebug "Layout machine type => $machineType, VirtualDesktop => $VirtualDesktop, Monitor => $monitorText"
	}

	# A failed collapse is reported instead of ignored: when it fails the move pass has to
	# relocate every window itself, so the run behaves very differently from a clean reset.
	$desktopCleanupResult = Remove-VirtualDesktops
	if (@($desktopCleanupResult) -contains $false) {
		Write-LogWarning "Virtual desktop cleanup did not complete - windows may still be spread across desktops."
	}

	$moveParams = @{
		VirtualDesktop = $VirtualDesktop
	}
	if ($Monitor) {
		$moveParams.Monitor = $Monitor
	}

	Move-Windows @moveParams

	# Center on the CONFIGURED monitor rather than letting Center-Windows re-derive one per
	# window. Center-Windows runs last, so passing the target makes the reset self-correcting:
	# any window that something else (for example FancyZones restoring a remembered zone after
	# the desktop collapse) pulled onto another monitor is brought back here instead of being
	# centered where it drifted to.
	$centerParams = @{}
	if ($Monitor) {
		$centerParams.Monitor = $Monitor
	}

	Center-Windows @centerParams

	Focus-TerminalTab
}
