function Open-Outlook {
	<#
	.SYNOPSIS
		Opens the new Outlook (Microsoft Store app).

	.DESCRIPTION
		Starts the modern Outlook application using Start-Application with configuration-driven
		executable path and AppsFolder argument.
		Does nothing if Outlook is already running.

	.EXAMPLE
		Open-Outlook
		Opens Outlook.
	#>
	Start-Application `
		-AppName "Outlook" `
		-ProcessName "olk" `
		-StartMethod ConfigPath `
		-ConfigKey "OutlookLauncherExe" `
		-Arguments "shell:AppsFolder\Microsoft.OutlookForWindows_8wekyb3d8bbwe!Microsoft.OutlookforWindows"
}
