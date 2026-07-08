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
		  3. Center-Windows          - center every window on its monitor

		This reproduces the manual sequence:
		  PC      => Remove-VirtualDesktops; Move-Windows -Monitor 2 -VirtualDesktop 1; Center-Windows
		  Laptop/ => Remove-VirtualDesktops; Move-Windows -VirtualDesktop 1; Center-Windows
		  Work

		Defaults for -VirtualDesktop and -Monitor are read per machine from
		$global:Configuration.ResetAllWindowsDefaults, keyed by the current
		machine type (PC, Laptop, Work, Test) as resolved by DetermineMachineType.
		On the PC, windows are consolidated onto monitor 2; on the laptop and work
		machines no monitor targeting is applied. Explicitly passing -VirtualDesktop
		or -Monitor overrides the configured default for that run.

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

	$machineType = DetermineMachineType

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
		Write-LogDebug "MachineType => $machineType, VirtualDesktop => $VirtualDesktop, Monitor => $monitorText"
	}

	Remove-VirtualDesktops

	$moveParams = @{
		VirtualDesktop = $VirtualDesktop
	}
	if ($Monitor) {
		$moveParams.Monitor = $Monitor
	}

	Move-Windows @moveParams

	Center-Windows

	Focus-TerminalTab
}
