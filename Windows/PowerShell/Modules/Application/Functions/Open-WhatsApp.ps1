function Open-WhatsApp {
	<#
	.SYNOPSIS
		Opens WhatsApp (Microsoft Store app).

	.DESCRIPTION
		Starts WhatsApp by activating its UWP package via its AppUserModelID using Start-Application.
		Does nothing if a WhatsApp window is already open.

		The "already running" check requires a visible main window (-RequireMainWindow). Windows
		COM-activates "WhatsApp.Root.exe -RegisterForBGTaskServer /nowindow /pushnotification" as a
		push notification host that lingers with no UI, and it runs under the same "WhatsApp.Root"
		process name the UI does, so a plain process-name check reports "already running" while
		nothing is on screen.

	.EXAMPLE
		Open-WhatsApp
		Opens WhatsApp.
	#>
	Start-Application `
		-AppName "WhatsApp" `
		-ProcessName "WhatsApp.Root" `
		-StartMethod AppxPackage `
		-PackageName "WhatsApp" `
		-RequireMainWindow
}
