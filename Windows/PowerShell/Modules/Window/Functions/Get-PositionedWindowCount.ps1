function Get-PositionedWindowCount {
	<#
	.SYNOPSIS
		Gets the count of tracked positioned windows.

	.DESCRIPTION
		Returns the number of window handles that have been registered as positioned
		by Set-WindowLayouts.

	.OUTPUTS
		Integer count of positioned windows.

	.EXAMPLE
		$count = Get-PositionedWindowCount
		Write-Host "There are $count positioned windows"
	#>
	[CmdletBinding()]
	param()

	if (-not $script:PositionedWindowHandles) {
		return 0
	}

	return $script:PositionedWindowHandles.Count
}
