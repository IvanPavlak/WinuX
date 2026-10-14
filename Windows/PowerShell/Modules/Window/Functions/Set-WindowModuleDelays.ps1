function Set-WindowModuleDelays {
	<#
	.SYNOPSIS
		Sets Window module timing configuration values.

	.DESCRIPTION
		Updates the module-scoped timing configuration with provided values.
		Only existing keys will be updated; unknown keys are ignored.

	.PARAMETER Delays
		Hashtable containing timing values to update. Valid keys:
		- CursorSettleMs: Delay after cursor movement before sending keys
		- FocusSettleMs: Delay after SetForegroundWindow before sending keys
		- KeyboardShortcutMs: Delay after keyboard shortcut is sent
		- LayoutCommitMs: Delay letting FancyZones commit a layout switch to disk before a
		  virtual-desktop switch fires
		- WindowRestoreMs: Delay after ShowWindow restore operations
		- WindowPositionMs: Delay after SetWindowPos for window to settle
		- VirtualDesktopMs: Delay after Move-Window for virtual desktop operations
		- AppliedLayoutsReloadMs: Delay after writing applied-layouts.json before the probe
		  shortcut that confirms FancyZones reloaded it
		Defaults (WindowModuleState.ps1): 25 for every key except AppliedLayoutsReloadMs (150).

	.EXAMPLE
		Set-WindowModuleDelays -Delays @{ FocusSettleMs = 10; WindowRestoreMs = 10 }
		Updates the focus settle and window restore delays to 10ms.
	#>
	param(
		[Parameter(Mandatory = $true)]
		[hashtable]$Delays
	)

	foreach ($key in $Delays.Keys) {
		if ($script:WindowModuleDelays.ContainsKey($key)) {
			$script:WindowModuleDelays[$key] = $Delays[$key]
		}
	}
}
