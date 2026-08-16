function Get-WindowInsetPercent {
	<#
	.SYNOPSIS
		Returns the pre-snap inset fraction every FancyZones placement path trims per side.

	.DESCRIPTION
		The single source of truth for $global:Configuration.SnapInsetPercent - the fraction
		of a zone trimmed off each side before the window is handed to FancyZones. The value
		reached five separate places as a hardcoded 0.05 (three parameter defaults and two
		local variables); this getter is what those five now call, so changing the inset is
		one config edit instead of five code edits that can silently drift apart.

		A getter rather than a module variable, because parameter defaults are evaluated at
		call time and the configuration is not loaded when the module is imported. Reading
		$global:Configuration on every call also means a reloaded profile takes effect
		immediately.

		Invalid configuration never throws. Anything non-numeric, or outside the 0.0-0.49
		range the ValidateRange on every consuming parameter accepts, falls back to the
		built-in 0.05 - a config typo must not abort a workspace open mid-loop. Note 0.49 is
		the ceiling because two insets of 0.5 would leave a zero-width window.

		Explicitly passing -InsetPercent still wins everywhere: a bound parameter never
		evaluates its default expression, which is how Center-Windows keeps its deliberate
		-InsetPercent 0 (exact placement, no inset).

	.OUTPUTS
		[double] The inset fraction applied per side, always within 0.0-0.49.

	.EXAMPLE
		Get-WindowInsetPercent
		# 0.05 by default; whatever SnapInsetPercent is set to otherwise
	#>
	[CmdletBinding()]
	[OutputType([double])]
	param ()

	# The historical default, and the answer whenever configuration cannot supply a usable one.
	$fallbackInset = 0.05

	if (-not $global:Configuration) {
		return $fallbackInset
	}

	$configured = $global:Configuration.SnapInsetPercent
	if ($null -eq $configured) {
		return $fallbackInset
	}

	if ($configured -is [array]) { $configured = @($configured)[0] }

	# Both of these cast to a perfectly valid 0.0 - PowerShell reads an empty string as zero
	# rather than failing - which would silently disable the inset instead of falling back.
	if ($configured -is [bool]) {
		return $fallbackInset
	}
	if ($configured -is [string] -and [string]::IsNullOrWhiteSpace($configured)) {
		return $fallbackInset
	}

	try { $inset = [double]$configured }
	catch { return $fallbackInset }

	if ($inset -lt 0.0 -or $inset -gt 0.49) {
		return $fallbackInset
	}

	return $inset
}
