function Set-LogLevel {
	<#
	.SYNOPSIS
		Sets the console verbosity for the logging engine, session-wide or scoped to a single command.

	.DESCRIPTION
		Controls which Write-Log* messages reach the console (file logging always records everything
		regardless of level):

		  Quiet   => only Warning and Error print to the console
		  Normal  => Title / Step / Success / Warning / Error print; Debug is hidden (default)
		  Verbose => everything prints, including Write-LogDebug diagnostics

		This is the cross-module verbosity control. The level is stored in the global logging state, so
		every function's Write-LogDebug output honors it with no parameter threading - including
		functions in other modules (module scope boundaries make the common -Verbose switch unreliable
		for nested calls, which is why this explicit control exists; a global
		$VerbosePreference = 'Continue' is also honored).

		Two forms:
		  Set-LogLevel Verbose                 -> persistent for the rest of the session
		  Set-LogLevel Verbose { Open-Workspace } -> scoped: runs the command (and everything it calls)
		                                              at that level, then restores the previous level.
		The scoped form turns diagnostics on for that one command and all underlying functions, with no
		parameter threading.

	.PARAMETER Level
		Quiet | Normal | Verbose.

	.PARAMETER Command
		Optional scriptblock. When supplied, the level applies only while the scriptblock runs and the
		previous level is restored afterward (even on error).

	.EXAMPLE
		Set-LogLevel Verbose
		Show debug diagnostics for the rest of the session.

	.EXAMPLE
		Set-LogLevel Verbose { Kill-All }
		Run Kill-All (and everything it calls) with diagnostics on, then restore the previous level.

	.EXAMPLE
		Set-LogLevel Normal
		Return to the default console verbosity.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateSet("Quiet", "Normal", "Verbose")]
		[string]$Level,

		[Parameter(Mandatory = $false, Position = 1)]
		[scriptblock]$Command
	)
	if (-not $global:LoggingState) {
		Initialize-LoggingState | Out-Null
	}

	if ($Command) {
		$previous = $global:LoggingState.Level
		$global:LoggingState.Level = $Level
		try { & $Command }
		finally { $global:LoggingState.Level = $previous }
	}
	else {
		$global:LoggingState.Level = $Level
	}
}
