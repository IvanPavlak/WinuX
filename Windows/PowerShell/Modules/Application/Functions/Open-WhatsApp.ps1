function Open-WhatsApp {
	<#
	.SYNOPSIS
		Opens WhatsApp (Microsoft Store app).

	.DESCRIPTION
		Starts WhatsApp by activating its UWP package via its AppUserModelID using Start-Application.
		Does nothing if WhatsApp is already running.

	.EXAMPLE
		Open-WhatsApp
		Opens WhatsApp.
	#>
	Start-Application `
		-AppName "WhatsApp" `
		-ProcessName "WhatsApp.Root" `
		-StartMethod AppxPackage `
		-PackageName "WhatsApp"
}
