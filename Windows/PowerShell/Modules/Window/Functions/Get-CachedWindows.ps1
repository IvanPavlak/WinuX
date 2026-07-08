function Get-CachedWindows {
	<#
	.SYNOPSIS
		Gets cached window enumeration results.

	.DESCRIPTION
		Returns window information from cache if still valid, otherwise
		refreshes the cache by calling the native EnumWindows function.
		This reduces repeated syscalls when multiple functions need window data.

	.OUTPUTS
		Array of window information from WindowModule.Native.GetAllWindows().

	.EXAMPLE
		$windows = Get-CachedWindows
		Gets all visible windows, using cache if available.
	#>
	$now = [datetime]::Now
	$age = ($now - $script:WindowCache.Timestamp).TotalMilliseconds

	if ($null -eq $script:WindowCache.Windows -or $age -gt $script:WindowCache.MaxAgeMs) {
		# Cache miss or expired - refresh
		$script:WindowCache.Windows = [WindowModule.Native]::GetAllWindows()
		$script:WindowCache.Timestamp = $now
	}

	return $script:WindowCache.Windows
}
