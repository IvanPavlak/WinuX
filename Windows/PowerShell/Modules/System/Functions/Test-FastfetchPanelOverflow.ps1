function Test-FastfetchPanelOverflow {
	<#
	.SYNOPSIS
		Tells whether a fastfetch panel of the given size overflows a window of the given size.

	.DESCRIPTION
		The fit rule Invoke-ClearAndFastfetch judges by, in one place. The panel overflows when
		it is wider than the window, or taller than the window minus one row for the line the
		cursor ends on and minus -PromptReserve rows for the upcoming prompt. A panel exactly as
		wide as the window fits.

		Pure: no console access, no side effects. That is what lets the auto-fit loop be tested
		against scripted window sizes, and lets a user check by hand whether a given panel would
		fit a given window.

	.PARAMETER PanelWidth
		Longest panel row, in cells.

	.PARAMETER PanelHeight
		Number of panel rows.

	.PARAMETER WindowWidth
		Window width, in cells.

	.PARAMETER WindowHeight
		Window height, in rows.

	.PARAMETER PromptReserve
		Rows kept free below the panel for the prompt. Default 1.

	.OUTPUTS
		[bool] - $true when the panel does not fit.

	.EXAMPLE
		Test-FastfetchPanelOverflow -PanelWidth 106 -PanelHeight 22 -WindowWidth 120 -WindowHeight 30
		$false - 106 columns fit in 120, and 22 rows leave the cursor row and one prompt row free in 30.

	.EXAMPLE
		Test-FastfetchPanelOverflow -PanelWidth 106 -PanelHeight 22 -WindowWidth 100 -WindowHeight 30
		$true - the panel is wider than the window.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory)]
		[int]$PanelWidth,

		[Parameter(Mandatory)]
		[int]$PanelHeight,

		[Parameter(Mandatory)]
		[int]$WindowWidth,

		[Parameter(Mandatory)]
		[int]$WindowHeight,

		[int]$PromptReserve = 1
	)

	$overflowsHeight = $PanelHeight -gt ($WindowHeight - 1 - $PromptReserve)
	$overflowsWidth = $PanelWidth -gt $WindowWidth

	return [bool]($overflowsHeight -or $overflowsWidth)
}
