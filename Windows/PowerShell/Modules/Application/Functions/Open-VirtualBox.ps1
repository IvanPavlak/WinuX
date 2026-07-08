function Open-VirtualBox {
	<#
	.SYNOPSIS
		Opens VirtualBox.

	.DESCRIPTION
		Starts VirtualBox using Start-Application. Does nothing if VirtualBox is already running.
		Executable path is read from the `VirtualBoxExe` key in the Universal configuration section.

	.EXAMPLE
		Open-VirtualBox
		Opens VirtualBox.
	#>
	Start-Application `
		-AppName "VirtualBox" `
		-ProcessName "VirtualBox" `
		-StartMethod ConfigPath `
		-ConfigKey "VirtualBoxExe" `
		-NoNewWindow
}
