function List-AvailableColors {
	<#
	.SYNOPSIS
		Display all available PowerShell console colors.

	.DESCRIPTION
		Shows a color palette with all combinations of foreground and background colors
		available in the PowerShell console. Useful for development and UI design.

	.EXAMPLE
		List-AvailableColors
	#>
	Write-Host -ForegroundColor DarkCyan "`n[Available PowerShell Colors]`n"
	$colors = [enum]::GetValues([System.ConsoleColor])

	foreach ($bgcolor in $colors) {
		foreach ($fgcolor in $colors) { Write-Host "$fgcolor|"  -ForegroundColor $fgcolor -BackgroundColor $bgcolor -NoNewline }
		Write-Host " on $bgcolor"
	}
}
