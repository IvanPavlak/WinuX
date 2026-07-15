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

	# Only touch files that are actually present. Explorer was stopped just above, but a file that
	# Get-ChildItem enumerated can disappear before Remove-Item reaches it, which otherwise surfaces
	# a "cannot find the file specified" error; re-check each file and ignore per-file failures.
	$iconCacheFolder = $Configuration.Universal.IconCacheFolder
	if ($iconCacheFolder -and (Test-Path -LiteralPath $iconCacheFolder)) {
		foreach ($iconCacheFile in @(Get-ChildItem -Path $iconCacheFolder -Filter "iconcache*" -ErrorAction SilentlyContinue)) {
			if (Test-Path -LiteralPath $iconCacheFile.FullName) {
				try { Remove-Item -LiteralPath $iconCacheFile.FullName -Force -ErrorAction Stop }
				catch { }
			}
		}
	}

	Write-LogStep " Starting Explorer..."
	Start-Process explorer.exe -ArgumentList "/factory,{682159d9-c321-47ca-b3f1-30e36b2ec8b9}"

	Write-LogSuccess "Icon cache rebuilt successfully!"
}
