function Open-WhatsApp {
	<#
	.SYNOPSIS
		Opens WhatsApp (Microsoft Store app).

	.DESCRIPTION
		Starts WhatsApp via its AppxPackage using Start-Application.
		Does nothing if WhatsApp is already running.

	.EXAMPLE
		Open-WhatsApp
		Opens WhatsApp.
	#>
	Start-Application `
		-AppName "WhatsApp" `
		-ProcessName "WhatsApp" `
		-StartMethod AppxPackage `
		-PackageName "WhatsApp" `
		-ExecutableName "WhatsApp.Root.exe"
}
