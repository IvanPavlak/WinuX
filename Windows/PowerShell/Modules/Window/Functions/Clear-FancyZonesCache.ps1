function Clear-FancyZonesCache {
	<#
	.SYNOPSIS
		Clears the FancyZones layout cache.

	.DESCRIPTION
		Invalidates the cached FancyZones layout data, forcing the next
		Get-CachedFancyZonesLayouts call to read from the JSON file.

	.EXAMPLE
		Clear-FancyZonesCache
		Clears the cache to force a reload of layout data.
	#>
	$script:FancyZonesCache.Data = $null
	$script:FancyZonesCache.Path = $null
	$script:FancyZonesCache.Timestamp = [datetime]::MinValue
}
