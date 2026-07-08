function Open-TeamViewer {
	<#
	.SYNOPSIS
		Opens TeamViewer.

	.DESCRIPTION
		Starts TeamViewer using Start-Application. Does nothing if TeamViewer is already running.
		Executable path is read from the `TeamViewerExe` key in the Universal configuration section.

	.EXAMPLE
		Open-TeamViewer
		Opens TeamViewer.
	#>
	Start-Application `
		-AppName "TeamViewer" `
		-ProcessName "TeamViewer" `
		-StartMethod ConfigPath `
		-ConfigKey "TeamViewerExe" `
		-NoNewWindow
}
