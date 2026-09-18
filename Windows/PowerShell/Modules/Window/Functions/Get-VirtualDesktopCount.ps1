function Get-VirtualDesktopCount {
	<#
	.SYNOPSIS
		Returns how many virtual desktops exist.

	.DESCRIPTION
		The count as the desktop manager reports it right now, read through
		Invoke-VirtualDesktopOperation so a stale COM session is reconnected rather than answering
		with yesterday's number. Because desktops are 0-based, the count is also the index the
		next desktop would get - which is what an -Alongside workspace open uses as its offset.

	.OUTPUTS
		[int] The number of virtual desktops. Throws when the desktop manager cannot be reached.

	.EXAMPLE
		$offset = Get-VirtualDesktopCount
		Opens the next workspace on the first desktop that does not exist yet.
	#>
	[CmdletBinding()]
	[OutputType([int])]
	param()

	return [int](Invoke-VirtualDesktopOperation -Operation { Get-DesktopCount } -Label 'counting virtual desktops')
}
