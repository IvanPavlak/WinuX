function Open-RiseupVPN {
	<#
	.SYNOPSIS
		Opens RiseupVPN.

	.DESCRIPTION
		DEPRECATED since 2.17.0, removed in 3.0.0: it serves one personal setup rather than
		the framework. It keeps working unchanged until then and warns once per session; to keep
		it, copy it into your fork's Custom area (Windows/PowerShell/Modules/Custom).

		Starts RiseupVPN using Start-Application. Does nothing if RiseupVPN is already running.
		Executable path is read from the `RiseupVpnExe` key in the Universal configuration section.

	.EXAMPLE
		Open-RiseupVPN
		Opens RiseupVPN.
	#>

	if (-not ($global:WinuXDeprecationWarned -is [System.Collections.IDictionary])) { $global:WinuXDeprecationWarned = @{} }
	if (-not $global:WinuXDeprecationWarned['Open-RiseupVPN']) {
		$global:WinuXDeprecationWarned['Open-RiseupVPN'] = $true
		Write-LogWarning "Open-RiseupVPN is deprecated since 2.17.0 and removed in 3.0.0 - copy it into your fork's Custom area (Windows/PowerShell/Modules/Custom) to keep using it"
	}

	Start-Application `
		-AppName "RiseupVPN" `
		-ProcessName "riseup-vpn" `
		-StartMethod ConfigPath `
		-ConfigKey "RiseupVpnExe" `
		-NoNewWindow
}
