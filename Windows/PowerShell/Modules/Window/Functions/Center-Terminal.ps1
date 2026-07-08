function Center-Terminal {
	<#
	.SYNOPSIS
		Centers the Windows Terminal on the primary monitor at a physically-constant size.

	.DESCRIPTION
		Re-centers the Windows Terminal window on whichever monitor is currently primary,
		sized so the terminal is roughly the SAME ON-SCREEN SIZE on every display.

		The width/height percentages are not fixed: they are derived at run time from the
		live primary monitor's work area and a target pixel size (CenterTerminalSizing in
		Configuration.psd1), then handed to Center-Windows. Because the size is computed
		from the live primary monitor (not the hostname-derived $global:MachineType), an
		undocked laptop on its small panel gets a proportionally larger window, while a
		docked laptop or the ultrawide stays at its usual size - without any per-machine
		configuration.

		Falls back to Center-Windows' default 40% x 50% when the config section or monitor
		information is unavailable.

		Placement is delegated to Center-Windows -OnPrimary, so window movement flows
		through the same single source of truth as the rest of the centering pipeline.

		Uses existing module functions:
		- Get-MonitorInfo for the live primary monitor work area
		- Resolve-CenteredWindowPercent for the target-px => percentage math (with clamps)
		- Center-Windows for the actual move/resize

	.EXAMPLE
		Center-Terminal
		Centers Windows Terminal on the primary monitor at the adaptive size.
	#>
	[CmdletBinding()]
	param()

	# Default to Center-Windows' legacy 40% x 50%. Only overridden when both the config
	# section and a primary monitor are available.
	$widthPercent = 40
	$heightPercent = 50

	$sizing = $global:Configuration.CenterTerminalSizing
	if ($sizing) {
		$monitors = Get-MonitorInfo -Quiet
		$primary = $monitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
		if (-not $primary -and $monitors) { $primary = $monitors[0] }

		if ($primary) {
			$resolved = Resolve-CenteredWindowPercent `
				-WorkAreaWidth $primary.WorkAreaWidth -WorkAreaHeight $primary.WorkAreaHeight `
				-TargetWidthPx $sizing.TargetWidthPx -TargetHeightPx $sizing.TargetHeightPx `
				-MinWidthPercent $sizing.MinWidthPercent -MaxWidthPercent $sizing.MaxWidthPercent `
				-MinHeightPercent $sizing.MinHeightPercent -MaxHeightPercent $sizing.MaxHeightPercent
			$widthPercent = $resolved.WidthPercent
			$heightPercent = $resolved.HeightPercent
		}
	}

	Center-Windows -ProcessName "WindowsTerminal" -OnPrimary -WidthPercent $widthPercent -HeightPercent $heightPercent
}
