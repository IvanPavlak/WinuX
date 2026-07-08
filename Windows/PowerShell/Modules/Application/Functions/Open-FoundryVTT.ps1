function Open-FoundryVTT {
	<#
	.SYNOPSIS
		Opens the FoundryVTT virtual tabletop server.

	.DESCRIPTION
		Starts the FoundryVTT desktop application using Start-Application.
		Does nothing if FoundryVTT is already running.
		Executable path is read from the `FoundryVTTExe` key in the Universal configuration section.

	.EXAMPLE
		Open-FoundryVTT
		Opens FoundryVTT.
	#>
	Start-Application `
		-AppName "FoundryVTT" `
		-ProcessName "Foundry Virtual Tabletop" `
		-StartMethod ConfigPath `
		-ConfigKey "FoundryVTTExe" `
		-NoNewWindow
}
