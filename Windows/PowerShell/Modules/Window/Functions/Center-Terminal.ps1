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
		docked laptop or the ultrawide stays at its usual size - so a single target already
		produces a uniform terminal everywhere, with no per-machine configuration required.

		The target itself can still be TUNED per machine: CenterTerminalSizing also accepts
		a keyed shape (SmallDisplay / machine type / Default rows) resolved by
		Resolve-CenterTerminalSizing, for when a particular display wants a different
		physical size rather than a different percentage of the same one. The legacy flat
		shape keeps working unchanged.

		Falls back to Center-Windows' default 40% x 50% when the config section resolves to
		nothing or monitor information is unavailable.

		Placement is delegated to Center-Windows -OnPrimary, so window movement flows
		through the same single source of truth as the rest of the centering pipeline.

		Uses existing module functions:
		- Get-MonitorInfo for the live primary monitor work area
		- Resolve-CenterTerminalSizing for the sizing block that applies to this display
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

	$section = $global:Configuration.CenterTerminalSizing
	if ($section) {
		$monitors = Get-MonitorInfo -Quiet
		$primary = $monitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
		if (-not $primary -and $monitors) { $primary = $monitors[0] }

		# Hand the snapshot over so the row resolution does not re-query the monitors.
		$sizing = Resolve-CenterTerminalSizing -Section $section -MonitorInfo $monitors

		if ($primary -and $sizing) {
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
