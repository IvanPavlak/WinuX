function Open-WSLTab {
	<#
	.SYNOPSIS
		Opens a new WSL tab in the current Windows Terminal window.

	.DESCRIPTION
		Opens a new tab in the focused Windows Terminal window using `wt.exe -w 0 new-tab`.
		The WSL distribution is read from `Configuration.DefaultWSLDistribution` in Configuration.psd1.

	.EXAMPLE
		Open-WSLTab
		Opens a new WSL tab in the current Windows Terminal window.
	#>
	$distro = $Configuration.DefaultWSLDistribution

	Write-LogTitle "Opening $distro WSL tab"

	try {
		& wt.exe -w 0 new-tab -p "$distro"
		Write-LogSuccess "$distro WSL tab opened successfully!"
	}
	catch {
		Write-LogError " Error => [$_]"
	}
}
