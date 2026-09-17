function Invoke-Clear {
	<#
	.SYNOPSIS
		Clears the terminal screen - the first step of Show-TerminalGreeting.

	.DESCRIPTION
		Runs `Clear-Host`, unless the greeting settings say the clear step is off.

		Thin by design. It exists so that all three greeting steps - clear, fastfetch, onefetch -
		are switched on and off the same way, from the same configuration section, and mocked the
		same way in the orchestrator's tests. A `Clear-Host` written inline in
		Show-TerminalGreeting would need its own `if`, its own configuration lookup and its own
		mocking seam, and would be the one step that could not be run or skipped on its own.

	.PARAMETER Settings
		The resolved greeting settings from Resolve-TerminalGreetingSettings. Show-TerminalGreeting
		resolves once and passes the tree down; omitted, this function resolves for itself, so it
		is usable on its own.

	.EXAMPLE
		Invoke-Clear
		Clears the screen, unless TerminalGreeting.Clear.Enabled is $false.

	.EXAMPLE
		Set-LogLevel Verbose { Invoke-Clear }
		Prints why the screen was not cleared, when it was not.
	#>
	[CmdletBinding()]
	param(
		[AllowNull()]
		[psobject]$Settings
	)

	if (-not $Settings) { $Settings = Resolve-TerminalGreetingSettings }

	if (-not $Settings.Clear.Enabled) {
		Write-LogDebug "[Invoke-Clear] skipped => TerminalGreeting.Clear.Enabled is false"
		return
	}

	Clear-Host
}
