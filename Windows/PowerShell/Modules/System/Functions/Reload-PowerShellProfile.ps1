function Reload-PowerShellProfile {
	<#
	.SYNOPSIS
		Reloads all custom modules and the PowerShell profile dot-sources.

	.DESCRIPTION
		First calls `Reload-CustomModules` to re-import all 9 custom modules,
		then dot-sources `AllUsersAllHosts` and `CurrentUserAllHosts` profile files
		to pick up any profile-level changes without restarting the terminal.

	.EXAMPLE
		Reload-PowerShellProfile
		Reloads all modules and profile scripts.
	#>
	[CmdletBinding()]
	param()

	Reload-CustomModules

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
