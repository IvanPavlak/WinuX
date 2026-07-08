function Open-Docker {
	<#
	.SYNOPSIS
		Starts Docker Desktop minimized to the system tray.

	.DESCRIPTION
		Starts Docker Desktop with the `--minimized` flag so it appears in the system tray
		without opening the main window. Electron and Bugsnag console output is suppressed via
		`-SuppressOutput`. Does nothing if Docker Desktop is already running.
		Executable path is read from the `DockerExe` key in the Universal configuration section.

	.EXAMPLE
		Open-Docker
		Starts Docker Desktop minimized to the tray.
	#>
	Start-Application `
		-AppName "Docker Desktop" `
		-ProcessName "Docker Desktop" `
		-StartMethod ConfigPath `
		-ConfigKey "DockerExe" `
		-Arguments "--minimized" `
		-SuppressOutput
}
