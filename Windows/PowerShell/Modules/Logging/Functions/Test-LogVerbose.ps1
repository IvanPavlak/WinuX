function Test-LogVerbose {
	<#
	.SYNOPSIS
		Returns $true when verbose logging is currently active.

	.DESCRIPTION
		The shared verbosity check that callers use to guard debug-only WORK (not just output) - for
		example `if (Test-LogVerbose) { $info = Get-ExpensiveDiagnostic; Write-LogDebug "Diag => $info" }`.
		It returns true when Set-LogLevel put the session (or a scoped command) into Verbose, or when a
		global $VerbosePreference = 'Continue' is in effect. Write-LogDebug applies the same check
		internally, so a bare Write-LogDebug needs no guard; use Test-LogVerbose only to also skip the
		surrounding computation when not verbose.

	.EXAMPLE
		if (Test-LogVerbose) {
			$updated = Get-WindowHandle -ProcessName $proc | Select-Object -First 1
			Write-LogDebug "Focused window => [$($updated.Title)]"
		}

	.EXAMPLE
		Set-LogLevel Verbose
		Test-LogVerbose   # -> $true
	#>
	[CmdletBinding()]
	param()
	if (-not $global:LoggingState) {
		Initialize-LoggingState | Out-Null
	}
	return ($global:LoggingState.Level -eq 'Verbose') -or ($VerbosePreference -ne 'SilentlyContinue')
}
