function Resolve-DisplayAwareProfile {
	<#
	.SYNOPSIS
		Picks the row of a display-aware configuration section that applies to this machine right now.

	.DESCRIPTION
		The shared row resolver for configuration sections whose value depends on the display
		the windows will land on (CenterTerminalSizing, ResizeWindowsPercent). A section is a
		hashtable of rows; this returns the value of the row that applies, in order:

		  1. SmallDisplay - present AND the live primary display is laptop-class
		     (Test-SmallPrimaryDisplay).
		  2. The row named after Get-LayoutMachineType, so LayoutMachineTypeOverrides and
		     SmallDisplayMachineType steer these sections exactly as they steer the layout
		     files and the Reset-Windows defaults.
		  3. Default.
		  4. $null - nothing matched; the caller applies its own built-in fallback.

		SmallDisplay is checked FIRST because the machine type cannot express it. A laptop
		reports the machine type "Laptop" both on its own panel and docked to a large external
		monitor, so a Laptop row alone can only be right in one of those two states. The
		SmallDisplay row is the state-dependent one: it wins while the small panel is primary
		and disappears the moment a big display takes over, at which point the ordinary type
		row (or Default) applies. A machine that never uses a laptop-class display simply
		omits the row and pays nothing - monitors are only queried when the row exists.

		Note the asymmetry with Get-LayoutMachineType, which deliberately checks its manual
		override BEFORE its display-size rule. There the override is an explicit human choice
		that a display-width guess must not overrule. Here there is no competing explicit
		choice: both candidate rows are configuration, and the more specific one - the one
		naming the actual display class - wins.

	.PARAMETER Section
		The configuration section to resolve, as a hashtable of rows keyed by machine type,
		plus the optional SmallDisplay and Default rows. Null or empty resolves to $null.

	.PARAMETER MonitorInfo
		Monitor records as returned by Get-MonitorInfo. Pass a snapshot the caller already
		holds to avoid re-querying; it is forwarded to both Test-SmallPrimaryDisplay and
		Get-LayoutMachineType. When omitted, each of them fetches monitors only if it
		actually needs them.

	.OUTPUTS
		The matching row's value (any type the section stores), or $null when nothing matched.

	.EXAMPLE
		Resolve-DisplayAwareProfile -Section $global:Configuration.ResizeWindowsPercent
		# 80 from the SmallDisplay row on the laptop panel; 70 from Default once docked

	.EXAMPLE
		Resolve-DisplayAwareProfile -Section $sizing -MonitorInfo $monitors
		# Reuses a monitor snapshot the caller already captured
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[hashtable]$Section,

		[Parameter()]
		[object[]]$MonitorInfo
	)

	if (-not $Section -or $Section.Count -eq 0) {
		return $null
	}

	# Forwarded only when the caller actually supplied a snapshot, so an unbound call leaves
	# both helpers free to skip the monitor query entirely.
	$monitorSplat = @{}
	if ($PSBoundParameters.ContainsKey('MonitorInfo')) {
		$monitorSplat['MonitorInfo'] = $MonitorInfo
	}

	if ($Section.ContainsKey('SmallDisplay') -and (Test-SmallPrimaryDisplay @monitorSplat)) {
		return $Section['SmallDisplay']
	}

	$machineType = Get-LayoutMachineType @monitorSplat
	if (-not [string]::IsNullOrWhiteSpace($machineType) -and $Section.ContainsKey($machineType)) {
		return $Section[$machineType]
	}

	if ($Section.ContainsKey('Default')) {
		return $Section['Default']
	}

	return $null
}
