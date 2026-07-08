function Clear-WindowCache {
	<#
	.SYNOPSIS
		Clears the window enumeration cache.

	.DESCRIPTION
		Invalidates the cached window information, forcing the next
		Get-CachedWindows call to refresh from the native API.
		Also clears the C# process name cache.

	.EXAMPLE
		Clear-WindowCache
		Clears the window cache to force a refresh.
	#>
	$script:WindowCache.Windows = $null
	$script:WindowCache.Timestamp = [datetime]::MinValue
	# Also clear the C# process name cache
	[WindowModule.Native]::ClearProcessCache()
}
