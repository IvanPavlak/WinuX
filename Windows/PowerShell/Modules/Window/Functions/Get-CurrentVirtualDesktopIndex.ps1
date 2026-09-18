function Get-CurrentVirtualDesktopIndex {
	<#
	.SYNOPSIS
		Returns the 0-based index of the virtual desktop currently on screen.

	.DESCRIPTION
		Read through Invoke-VirtualDesktopOperation, so a stale COM session is reconnected
		rather than reporting the desktop that was showing before an Explorer restart.

	.OUTPUTS
		[int] The current desktop's 0-based index. Throws when the desktop manager cannot be reached.

	.EXAMPLE
		$returnTo = Get-CurrentVirtualDesktopIndex
		# ... switch around ...
		[void](Switch-VirtualDesktop -Index $returnTo)
	#>
	[CmdletBinding()]
	[OutputType([int])]
	param()

	return [int](Invoke-VirtualDesktopOperation -Operation { Get-DesktopIndex -Desktop (Get-CurrentDesktop) } -Label 'reading the current virtual desktop')
}
