function Open-LeagueOfLegends {
	<#
	.SYNOPSIS
		Opens the League of Legends client.

	.DESCRIPTION
		DEPRECATED since 2.17.0, removed in 3.0.0: it serves one personal setup rather than
		the framework. It keeps working unchanged until then and warns once per session; to keep
		it, copy it into your fork's Custom area (Windows/PowerShell/Modules/Custom).

		Starts the League of Legends client using Start-Application.
		Does nothing if the client is already running.
		Executable path is read from `Configuration.Universal.LeagueOfLegendsExe`.

	.EXAMPLE
		Open-LeagueOfLegends
		Opens the League of Legends client.
	#>

	if (-not ($global:WinuXDeprecationWarned -is [System.Collections.IDictionary])) { $global:WinuXDeprecationWarned = @{} }
	if (-not $global:WinuXDeprecationWarned['Open-LeagueOfLegends']) {
		$global:WinuXDeprecationWarned['Open-LeagueOfLegends'] = $true
		Write-LogWarning "Open-LeagueOfLegends is deprecated since 2.17.0 and removed in 3.0.0 - copy it into your fork's Custom area (Windows/PowerShell/Modules/Custom) to keep using it"
	}

	Start-Application `
		-AppName "League of Legends" `
		-ProcessName "LeagueClient" `
		-StartMethod DirectPath `
		-ExecutablePath (Get-ConfigSetting -Path 'Universal.LeagueOfLegendsExe') `
		-SkipPathValidation
}
