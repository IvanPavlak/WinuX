function Set-WindowCacheMaxAge {
	<#
	.SYNOPSIS
		Sets the maximum age for the window cache.

	.DESCRIPTION
		Configures how long the window enumeration cache remains valid.
		Lower values provide more accurate data at the cost of more syscalls.

	.PARAMETER MaxAgeMs
		Maximum cache age in milliseconds. Default is 50ms.

	.EXAMPLE
		Set-WindowCacheMaxAge -MaxAgeMs 100
		Sets the cache to remain valid for 100 milliseconds.
	#>
	param(
		[Parameter(Mandatory = $true)]
		[int]$MaxAgeMs
	)

	$script:WindowCache.MaxAgeMs = $MaxAgeMs
}
