function Rebuild-IconCache {
	<#
	.SYNOPSIS
		Clears the Windows icon cache and restarts Explorer.

	.DESCRIPTION
		Stops Explorer, deletes the icon cache database (`IconCache.db`) from the path
		configured in `Configuration.Universal.IconCacheDb`, then restarts Explorer.
		Fixes missing or corrupted desktop/taskbar icons.
		Requires administrator privileges.

	.EXAMPLE
		Rebuild-IconCache
		Clears the icon cache and restarts Explorer.
	#>
	Write-LogTitle "Rebuilding Icon Cache"

	Write-LogStep " Stopping Explorer..."
	Stop-Process -ProcessName explorer -Force -ErrorAction SilentlyContinue

	Start-Sleep -Seconds 1

	Write-LogStep " Deleting icon cache files..."
	$iconCachePath = $Configuration.Universal.IconCacheDb

	if (Test-Path $iconCachePath) {
		Remove-Item -Path $iconCachePath -Force -ErrorAction SilentlyContinue
	}

	Get-ChildItem -Path $Configuration.Universal.IconCacheFolder -Filter "iconcache*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

	Write-LogStep " Starting Explorer..."
	Start-Process explorer.exe -ArgumentList "/factory,{682159d9-c321-47ca-b3f1-30e36b2ec8b9}"

	Write-LogSuccess "Icon cache rebuilt successfully!"
}
