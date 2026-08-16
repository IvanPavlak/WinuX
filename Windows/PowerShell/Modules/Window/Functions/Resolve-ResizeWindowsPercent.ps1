function Resolve-ResizeWindowsPercent {
	<#
	.SYNOPSIS
		Resolves the percentage Resize-Windows shrinks windows by when no -Percent is given.

	.DESCRIPTION
		Reads $global:Configuration.ResizeWindowsPercent through Resolve-DisplayAwareProfile,
		so the default scale follows the display in use: the SmallDisplay row while a
		laptop-class panel is primary, otherwise the machine type's row, otherwise Default.

		This is what makes the workspace flow behave the same everywhere. Resize-Windows'
		percent mode is the first-open normalization and retry step of
		Set-WorkspaceWindowLayout, and those call sites pass no -Percent at all. A single
		hardcoded 70 has to be a compromise: it is a mild shrink on a wide monitor and an
		aggressive one on a laptop panel, where the window has far less room to give up.
		Configuring it per display lets each machine keep windows at a comfortable size.

		Invalid configuration never throws. Anything non-numeric, or outside the 10-500 range
		Resize-Windows' own ValidateRange accepts, falls back to the built-in 70 - a typo in
		a config file must not abort a workspace open mid-loop.

	.PARAMETER MonitorInfo
		Monitor records as returned by Get-MonitorInfo, forwarded to the row resolver so a
		caller that already holds a snapshot does not pay for a second query.

	.OUTPUTS
		[int] The resize percentage, always within 10-500.

	.EXAMPLE
		Resolve-ResizeWindowsPercent
		# 80 on the laptop panel (SmallDisplay row), 70 docked or on the PC (Default row)

	.EXAMPLE
		Resolve-ResizeWindowsPercent -MonitorInfo $monitors
		# Reuses a monitor snapshot the caller already captured
	#>
	[CmdletBinding()]
	[OutputType([int])]
	param (
		[Parameter()]
		[object[]]$MonitorInfo
	)

	# The historical default, and the answer whenever configuration cannot supply a usable one.
	$fallbackPercent = 70

	if (-not $global:Configuration) {
		return $fallbackPercent
	}

	$section = $global:Configuration.ResizeWindowsPercent
	if ($section -isnot [hashtable]) {
		return $fallbackPercent
	}

	$resolveSplat = @{ Section = $section }
	if ($PSBoundParameters.ContainsKey('MonitorInfo')) {
		$resolveSplat['MonitorInfo'] = $MonitorInfo
	}

	$configured = Resolve-DisplayAwareProfile @resolveSplat
	if ($null -eq $configured) {
		return $fallbackPercent
	}

	if ($configured -is [array]) { $configured = @($configured)[0] }

	# PowerShell reads an empty string as zero rather than failing the cast; 0 is out of range
	# here anyway, but rejecting it up front keeps the intent obvious.
	if ($configured -is [string] -and [string]::IsNullOrWhiteSpace($configured)) {
		return $fallbackPercent
	}

	try { $percent = [int][Math]::Round([double]$configured) }
	catch { return $fallbackPercent }

	if ($percent -lt 10 -or $percent -gt 500) {
		return $fallbackPercent
	}

	return $percent
}
