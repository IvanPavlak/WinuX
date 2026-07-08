function Clear-MonitorCache {
	<#
	.SYNOPSIS
		Clears the monitor information cache.

	.DESCRIPTION
		Invalidates the cached monitor data, forcing the next
		Get-CachedMonitors call to refresh from the Windows Forms API.
		Useful when monitor configuration changes.

	.EXAMPLE
		Clear-MonitorCache
		Clears the cache to detect new monitor configurations.
	#>
	$script:MonitorCache.Monitors = $null
	$script:MonitorCache.Timestamp = [datetime]::MinValue
}
