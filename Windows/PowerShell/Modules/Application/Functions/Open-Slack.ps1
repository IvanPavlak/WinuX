function Open-Slack {
	<#
	.SYNOPSIS
		Opens Slack.

	.DESCRIPTION
		Starts Slack using Start-Application via its local electron launcher.
		Does nothing if Slack is already running.

	.EXAMPLE
		Open-Slack
		Opens Slack.
	#>
	Start-Application `
		-AppName "Slack" `
		-ProcessName "slack" `
		-StartMethod DirectPath `
		-ExecutablePath "$env:LOCALAPPDATA\slack\slack.exe" `
		-Arguments "--processStart", "slack.exe"
}
