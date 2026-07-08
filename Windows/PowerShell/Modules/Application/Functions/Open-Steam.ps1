function Open-Steam {
	<#
	.SYNOPSIS
		Opens Steam.

	.DESCRIPTION
		Starts Steam using Start-Application. Does nothing if Steam is already running.
		Executable path is read from `Configuration.Universal.SteamExe`.

	.EXAMPLE
		Open-Steam
		Opens Steam.
	#>
	Start-Application `
		-AppName "Steam" `
		-ProcessName "steamwebhelper" `
		-StartMethod DirectPath `
		-ExecutablePath $Configuration.Universal.SteamExe `
		-SkipPathValidation
}
