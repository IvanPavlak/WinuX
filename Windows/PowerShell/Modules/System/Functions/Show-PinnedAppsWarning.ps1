function Show-PinnedAppsWarning {
	<#
	.SYNOPSIS
		Displays a warning about pinned (version-locked) apps that will be skipped.

	.DESCRIPTION
		Prints a yellow warning message listing apps that are pinned to a specific version
		and will not be updated by the upgrade functions.

	.PARAMETER PinnedApps
		Array of pinned app names to display.

	.PARAMETER Message
		Custom warning message prefix. Defaults to "Skipping version-pinned packages".

	.EXAMPLE
		Show-PinnedAppsWarning -PinnedApps @("git", "nodejs") -Message "Version-locked packages"
		Displays a warning about the specified pinned packages.
	#>
	param (
		[array]$PinnedApps,
		[string]$Message = "Skipping version-pinned packages"
	)

	if ($PinnedApps.Count -gt 0) {
		Write-LogWarning "$Message"
		foreach ($app in $PinnedApps) {
			Write-Host -ForegroundColor Yellow "  - $app"
		}
		Write-Host ""
	}
}
