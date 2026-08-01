function Get-LayoutMachineType {
	<#
	.SYNOPSIS
		Resolves the machine type whose window-arrangement settings apply to the current display setup.

	.DESCRIPTION
		Window layouts and the Reset-Windows defaults describe a machine's MONITORS rather than its
		identity, and monitors change: a desktop moved away from its multi-monitor rig, a temporary
		single screen, a laptop-class display. This resolves the machine type those display-shaped
		settings should be read under, in order:

		  1. $Configuration.LayoutMachineTypeOverrides[<detected type>] - a non-empty value replaces
		     the machine type. This is the manual switch: point it at a separate layout set, clear it
		     to go back, without ever editing the machine's real layouts.
		  2. $Configuration.SmallDisplayMachineType - used when no override applies and the primary
		     display is at most 3000px wide (laptop-class). Empty/unset disables it.
		  3. The detected machine type from DetermineMachineType.

		The override is deliberately checked FIRST: an explicit choice must not be overruled by a
		display-width guess, which is exactly what a temporary single screen would trigger.

		Only display-shaped settings resolve through this. Everything else keyed by machine type
		(base paths, symbolic links, wallpapers, themes, taskbar) keeps using DetermineMachineType,
		so a redirect never relocates a path or repaints a desktop.

		Consumers: Set-WorkspaceWindowLayout (which Layouts/<Type>/ folder and <Workspace>_<Type>.psd1
		file to load) and Reset-Windows (which ResetAllWindowsDefaults profile to apply). Both are
		answers to the same question - "which monitor setup am I on?" - so they share one resolution.

	.PARAMETER MonitorInfo
		Monitor records as returned by Get-MonitorInfo. Pass a snapshot the caller already holds to
		avoid re-querying. When omitted, monitors are fetched only if the small-display rule is
		actually reachable (no override matched and SmallDisplayMachineType is configured).

	.OUTPUTS
		[string] The machine type to read window-arrangement settings under.

	.EXAMPLE
		Get-LayoutMachineType
		# "PC" normally; "Temp" when LayoutMachineTypeOverrides.PC = "Temp"

	.EXAMPLE
		Get-LayoutMachineType -MonitorInfo $cachedMonitorInfo
		# Reuses a monitor snapshot the caller already captured
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param (
		[Parameter()]
		[object[]]$MonitorInfo
	)

	$machineType = DetermineMachineType

	# Manual override wins outright - see .DESCRIPTION for why it is ordered ahead of the
	# display-size rule.
	if ($Configuration.LayoutMachineTypeOverrides) {
		$configuredOverride = $Configuration.LayoutMachineTypeOverrides[$machineType]
		if ($configuredOverride -is [array]) { $configuredOverride = @($configuredOverride)[0] }
		if (-not [string]::IsNullOrWhiteSpace($configuredOverride)) {
			$overrideType = ([string]$configuredOverride).Trim()
			Write-LogDebug " Layout override configured for [$machineType] => using [$overrideType] layout set" -Style Warning
			return $overrideType
		}
	}

	$smallDisplayType = $Configuration.SmallDisplayMachineType
	if ([string]::IsNullOrWhiteSpace($smallDisplayType)) {
		return $machineType
	}

	# Monitors are queried only once an override has been ruled out AND a small-display type is
	# configured, so the common path costs nothing beyond the machine-type lookup.
	$monitors = if ($PSBoundParameters.ContainsKey('MonitorInfo')) { $MonitorInfo } else { Get-MonitorInfo -Quiet }
	if (-not $monitors) {
		return $machineType
	}

	$primaryMonitor = $monitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
	if (-not $primaryMonitor) {
		$primaryMonitor = $monitors | Select-Object -First 1
	}

	if ($primaryMonitor -and $primaryMonitor.Width -le 3000) {
		Write-LogDebug " Detected small display ($($primaryMonitor.Width)x$($primaryMonitor.Height)) => using $smallDisplayType layout" -Style Warning
		return $smallDisplayType
	}

	return $machineType
}
