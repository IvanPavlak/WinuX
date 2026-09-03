function Send-FancyZonesLayoutShortcut {
	<#
	.SYNOPSIS
		Sends the FancyZones Win+Ctrl+Alt+[Number] layout shortcut for the monitor at a given rectangle.

	.DESCRIPTION
		FancyZones applies a quick-layout shortcut to the monitor under the mouse cursor, on the
		active virtual desktop. This function moves the cursor to the center of the given monitor
		rectangle, gives the desktop window the foreground so no application swallows the chord, and
		injects Win+Ctrl+Alt+[Number] through the batched SendInput helper in WindowNative.cs. The
		three short settle delays between the steps come from Get-WindowModuleDelays
		(CursorSettleMs, FocusSettleMs, KeyboardShortcutMs).

		Apply-FancyZones uses it for every monitor/desktop pair of its shortcut pass and for the
		single probe shortcut that confirms FancyZones reloaded applied-layouts.json after a file
		write. It sends real input: never call it from a test.

	.PARAMETER LayoutNumber
		The hotkey slot 0-9 (Configuration.LayoutNumbers maps layout names to these).

	.PARAMETER MonitorX
		Left edge of the monitor, in virtual-screen pixels.

	.PARAMETER MonitorY
		Top edge of the monitor, in virtual-screen pixels.

	.PARAMETER MonitorWidth
		Width of the monitor in pixels.

	.PARAMETER MonitorHeight
		Height of the monitor in pixels.

	.EXAMPLE
		Send-FancyZonesLayoutShortcut -LayoutNumber 5 -MonitorX 0 -MonitorY 0 -MonitorWidth 3440 -MonitorHeight 1440
		# Applies hotkey layout 5 to the 3440x1440 monitor at the origin, on the active desktop.

	.NOTES
		Requires the WindowModule.Native type that Window.psm1 compiles from WindowNative.cs.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[ValidateRange(0, 9)]
		[int]$LayoutNumber,

		[Parameter(Mandatory = $true)]
		[int]$MonitorX,

		[Parameter(Mandatory = $true)]
		[int]$MonitorY,

		[Parameter(Mandatory = $true)]
		[int]$MonitorWidth,

		[Parameter(Mandatory = $true)]
		[int]$MonitorHeight
	)

	# Move the cursor to the monitor's center - FancyZones targets the monitor under the cursor.
	$cursorX = [int]($MonitorX + ($MonitorWidth / 2))
	$cursorY = [int]($MonitorY + ($MonitorHeight / 2))

	if (Test-LogVerbose) {
		Write-LogDebug "Moving cursor to monitor center ($cursorX, $cursorY)" -Style Step
	}
	[void][WindowModule.Native]::SetCursorPos($cursorX, $cursorY)
	Start-Sleep -Milliseconds $script:WindowModuleDelays.CursorSettleMs

	$desktopHandle = [WindowModule.Native]::GetDesktopWindow()
	[void][WindowModule.Native]::SetForegroundWindow($desktopHandle)
	Start-Sleep -Milliseconds $script:WindowModuleDelays.FocusSettleMs

	if (Test-LogVerbose) {
		Write-LogDebug "Sending keyboard shortcut [Win+Ctrl+Alt+$LayoutNumber]" -Style Step
	}
	[WindowModule.Native]::SendFancyZonesLayoutShortcut($LayoutNumber)
	Start-Sleep -Milliseconds $script:WindowModuleDelays.KeyboardShortcutMs
}
