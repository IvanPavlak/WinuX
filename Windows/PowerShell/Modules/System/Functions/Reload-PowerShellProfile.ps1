function Reload-PowerShellProfile {
	<#
	.SYNOPSIS
		Reloads all WinuX modules and the PowerShell profile dot-sources.

	.DESCRIPTION
		First calls `Reload-WinuXModules` to re-import all WinuX modules (including the
		Custom area), then dot-sources each of the `AllUsersAllHosts`, `AllUsersCurrentHost`,
		`CurrentUserAllHosts` and `CurrentUserCurrentHost` profile files that exist, to pick up any
		profile-level changes without restarting the terminal. Under verbose logging (or -Verbose)
		the header and success banner are suppressed and each sourced file is logged instead.

	.EXAMPLE
		Reload-PowerShellProfile
		Reloads all modules and profile scripts.
	#>
	[CmdletBinding()]
	param()

	Reload-WinuXModules

	if (-not (Test-LogVerbose)) {
		Write-LogTitle "Reloading PowerShell Profile" -BlankLineAfter
	}

	@(
		$Profile.AllUsersAllHosts,
		$Profile.AllUsersCurrentHost,
		$Profile.CurrentUserAllHosts,
		$Profile.CurrentUserCurrentHost
	) | ForEach-Object {
		if (Test-Path $_) {
			Write-Verbose "Running $_"
			. $_
		}
	}

	if (-not (Test-LogVerbose)) {
		Write-LogSuccess "PowerShell Profile reloaded successfully!" -BlankLineAfter
	}
}
