function Open-Discord {
	<#
	.SYNOPSIS
		Opens Discord.

	.DESCRIPTION
		Starts Discord using Start-Application via its Update.exe launcher.
		Does nothing if Discord is already running.

	.EXAMPLE
		Open-Discord
		Opens Discord.
	#>
	$discordPath = "$env:LOCALAPPDATA\Discord\Update.exe"

	Start-Application `
		-AppName "Discord" `
		-ProcessName "Discord" `
		-StartMethod DirectPath `
		-ExecutablePath $discordPath `
		-Arguments "--processStart", "Discord.exe" `
		-NoNewWindow
}
