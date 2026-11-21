function Open-FoundryVTT {
	<#
	.SYNOPSIS
		Opens the FoundryVTT virtual tabletop server.

	.DESCRIPTION
		DEPRECATED since 2.17.0, removed in 3.0.0: it serves one personal setup rather than
		the framework. It keeps working unchanged until then and warns once per session; to keep
		it, copy it into your fork's Custom area (Windows/PowerShell/Modules/Custom).

		Starts the FoundryVTT desktop application using Start-Application.
		Does nothing if FoundryVTT is already running.
		Executable path is read from the `FoundryVTTExe` key in the Universal configuration section.

	.EXAMPLE
		Open-FoundryVTT
		Opens FoundryVTT.
	#>

	if (-not ($global:WinuXDeprecationWarned -is [System.Collections.IDictionary])) { $global:WinuXDeprecationWarned = @{} }
	if (-not $global:WinuXDeprecationWarned['Open-FoundryVTT']) {
		$global:WinuXDeprecationWarned['Open-FoundryVTT'] = $true
		Write-LogWarning "Open-FoundryVTT is deprecated since 2.17.0 and removed in 3.0.0 - copy it into your fork's Custom area (Windows/PowerShell/Modules/Custom) to keep using it"
	}

	Start-Application `
		-AppName "FoundryVTT" `
		-ProcessName "Foundry Virtual Tabletop" `
		-StartMethod ConfigPath `
		-ConfigKey "FoundryVTTExe" `
		-NoNewWindow
}
