function Open-LeagueOfLegends {
	<#
	.SYNOPSIS
		Opens the League of Legends client.

	.DESCRIPTION
		Starts the League of Legends client using Start-Application.
		Does nothing if the client is already running.
		Executable path is read from `Configuration.Universal.LeagueOfLegendsExe`.

	.EXAMPLE
		Open-LeagueOfLegends
		Opens the League of Legends client.
	#>
	Start-Application `
		-AppName "League of Legends" `
		-ProcessName "LeagueClient" `
		-StartMethod DirectPath `
		-ExecutablePath $Configuration.Universal.LeagueOfLegendsExe `
		-SkipPathValidation
}
