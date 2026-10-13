function Open-Outlook {
	<#
	.SYNOPSIS
		Opens the new Outlook (Microsoft Store app).

	.DESCRIPTION
		Starts the modern Outlook application using Start-Application: the launcher executable is
		read from the `OutlookLauncherExe` key in the Universal configuration section (explorer.exe
		by default), and the Outlook shell:AppsFolder argument is fixed.
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
