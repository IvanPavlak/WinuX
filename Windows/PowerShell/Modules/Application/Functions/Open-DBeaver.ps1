function Open-DBeaver {
	<#
	.SYNOPSIS
		Opens DBeaver database client.

	.DESCRIPTION
		Starts DBeaver using Start-Application. Does nothing if DBeaver is already running.
		Executable path is read from the `DbeaverExe` key in the Universal configuration section.

	.EXAMPLE
		Open-DBeaver
		Opens DBeaver.
	#>
	Start-Application `
		-AppName "DBeaver" `
		-ProcessName "dbeaver" `
		-StartMethod ConfigPath `
		-ConfigKey "DbeaverExe" `
		-NoNewWindow
}
