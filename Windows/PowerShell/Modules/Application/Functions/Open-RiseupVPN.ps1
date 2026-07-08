function Open-RiseupVPN {
	<#
	.SYNOPSIS
		Opens RiseupVPN.

	.DESCRIPTION
		Starts RiseupVPN using Start-Application. Does nothing if RiseupVPN is already running.
		Executable path is read from the `RiseupVpnExe` key in the Universal configuration section.

	.EXAMPLE
		Open-RiseupVPN
		Opens RiseupVPN.
	#>
	Start-Application `
		-AppName "RiseupVPN" `
		-ProcessName "riseup-vpn" `
		-StartMethod ConfigPath `
		-ConfigKey "RiseupVpnExe" `
		-NoNewWindow
}
