function Confirm-ConfigValue {
	<#
	.SYNOPSIS
		Tests whether a configuration value is configured, warning when it is not.

	.DESCRIPTION
		The standard unconfigured-section guard for the empty-by-default
		configuration: Test-ConfigValue plus the "not configured" warning in one
		call. Returns $true when the value is configured; otherwise writes the
		given warning (unless -Quiet) and returns $false. PowerShell cannot
		return across scopes, so the early return stays at the call site:

			if (-not (Confirm-ConfigValue $Configuration.Themes "Themes not configured - leaving system theme as-is!")) {
				return
			}

		Use plain Test-ConfigValue when no warning should be emitted (pure
		checks, Debug-level paths, or custom log formatting).

	.PARAMETER Value
		The configuration value to test. Accepts $null. Unconfigured shapes:
		$null, empty/whitespace string, empty array/collection, empty hashtable.

	.PARAMETER WarningMessage
		The warning written via Write-LogWarning when the value is unconfigured.

	.PARAMETER Quiet
		Suppresses the warning; the boolean result is unchanged. Pass through a
		caller's own -Quiet switch, e.g. -Quiet:$Quiet.

	.EXAMPLE
		if (-not (Confirm-ConfigValue $Configuration.NerdFonts "NerdFonts not configured - no font to install!")) {
			return
		}

	.EXAMPLE
		if (-not (Confirm-ConfigValue $wolConfig "Wake-on-LAN not configured (WakeOnLanConfig)!" -Quiet:$Quiet)) {
			return $false
		}
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Position = 0)]
		[AllowNull()]
		$Value,

		[Parameter(Mandatory, Position = 1)]
		[string]$WarningMessage,

		[Parameter()]
		[switch]$Quiet
	)

	if (Test-ConfigValue $Value) {
		return $true
	}

	if (-not $Quiet) {
		Write-LogWarning $WarningMessage
	}

	return $false
}
