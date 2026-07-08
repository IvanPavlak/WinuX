function Open-SecureBrowser {
	<#
	.SYNOPSIS
		Establishes a VPN-protected Tor Browser session with IP verification.

	.DESCRIPTION
		Runs a multi-step privacy workflow:
		1. Retrieves the current ISP IP address before connecting the VPN
		2. Starts RiseupVPN
		3. Waits for manual confirmation that the VPN is connected
		4. Hides the RiseupVPN window to the system tray (Win32 ShowWindow SW_HIDE)
		5. Opens Tor Browser
		6. Waits 5 seconds for Tor Browser to initialize
		7. Calls Test-PrivacyStatus in Tor mode to verify the IP has changed

		Requires the Window module to be loaded (for Win32 ShowWindow access).

	.EXAMPLE
		Open-SecureBrowser
		Starts the full VPN + Tor Browser privacy session.
	#>
	Write-LogTitle "Initializing Secure Browsing"

	# Get ISP IP BEFORE connecting VPN
	try {
		$ISPIPAddress = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -TimeoutSec 5 -ErrorAction Stop).ip
		Write-LogSuccess " ISP IP Address => [$ISPIPAddress]"
	}
	catch {
		$ISPIPAddress = $null
		Write-LogWarning "Could not retrieve ISP IP address (will attempt later)" -NoLeadingNewline
	}

	Open-RiseupVPN

	Resolve-Selection -MenuTitle "[Is RiseupVPN connected?]" -HideSelection -PromptMessage "Press any key to continue after RiseupVPN connection is secured..." -AllowEmptyPromptResponse:$true

	# Hide RiseupVPN window to tray after manual connection
	$vpnHandle = (Get-Process -Name "riseup-vpn" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }).MainWindowHandle
	if ($vpnHandle) {
		[void][WindowModule.Native]::ShowWindow($vpnHandle, [WindowModule.Native]::SW_HIDE)
	}

	try {
		Open-Browser -Browser Tor -NoMenu

		Loading-Spinner -Function { Start-Sleep -Seconds 5 } -Label "Waiting for Tor Browser to initialize..."

		# Verify privacy status with Tor mode
		Test-PrivacyStatus -ISPIPAddress $ISPIPAddress -UseTor
	}
	catch {
		Write-LogError "Error: [$($_.Exception.Message)]"
	}
}
