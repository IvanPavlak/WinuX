function Set-WindowPosition {
	<#
	.SYNOPSIS
		Sets the position and size of a window.

	.DESCRIPTION
		Moves and resizes a window to specific coordinates. This can be used to position
		windows to match FancyZones layouts by calculating the zone coordinates.

	.PARAMETER WindowHandle
		The window handle (HWND) to move.

	.PARAMETER X
		The X coordinate (left position) in pixels.

	.PARAMETER Y
		The Y coordinate (top position) in pixels.

	.PARAMETER Width
		The width of the window in pixels.

	.PARAMETER Height
		The height of the window in pixels.

	.EXAMPLE
		$handle = (Get-WindowHandle -ProcessName "chrome")[0].Handle
		Set-WindowPosition -WindowHandle $handle -X 0 -Y 0 -Width 1920 -Height 1080

	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[IntPtr]$WindowHandle,

		[Parameter(Mandatory = $true)]
		[int]$X,

		[Parameter(Mandatory = $true)]
		[int]$Y,

		[Parameter(Mandatory = $true)]
		[int]$Width,

		[Parameter(Mandatory = $true)]
		[int]$Height
	)

	# Use consolidated native types from WindowNative.cs (loaded in Window.psm1)
	try {
		# First, ensure window is not maximized or minimized
		$isMaximized = [WindowModule.Native]::IsZoomed($WindowHandle)

		if ($isMaximized) {
			Write-LogDebug "  Restoring window from maximized state..." -Style Step
			[void][WindowModule.Native]::ShowWindow($WindowHandle, [WindowModule.Native]::SW_RESTORE)
			Start-Sleep -Milliseconds $script:WindowModuleDelays.WindowRestoreMs
		}

		# Restore to normal state (handles snapped/minimized windows). The settle delay is
		# only paid when the window was NOT already in the normal show state - the previous
		# unconditional sleep added a fixed 25ms to every call in the positioning pipeline
		# (~35 calls per workspace open).
		$placement = New-Object WindowModule.WINDOWPLACEMENT
		$placement.length = [System.Runtime.InteropServices.Marshal]::SizeOf([type][WindowModule.WINDOWPLACEMENT])
		$wasAlreadyNormal = $false
		if ([WindowModule.Native]::GetWindowPlacement($WindowHandle, [ref]$placement)) {
			$wasAlreadyNormal = ($placement.showCmd -eq [WindowModule.Native]::SW_SHOWNORMAL)
		}

		[void][WindowModule.Native]::ShowWindow($WindowHandle, [WindowModule.Native]::SW_SHOWNORMAL)
		if (-not $wasAlreadyNormal) {
			Start-Sleep -Milliseconds $script:WindowModuleDelays.WindowRestoreMs
		}

		# Set window position and size
		# Use FRAMECHANGED to ensure window updates properly
		$flags = [WindowModule.Native]::SWP_NOZORDER -bor [WindowModule.Native]::SWP_SHOWWINDOW -bor [WindowModule.Native]::SWP_FRAMECHANGED

		$result = [WindowModule.Native]::SetWindowPos(
			$WindowHandle,
			[IntPtr]::Zero,
			$X,
			$Y,
			$Width,
			$Height,
			$flags
		)

		if ($result) {
			# No fixed settle delay here: every caller either verifies the rect afterwards
			# (Wait-WindowRect / explicit re-reads) or sleeps on its own schedule.
			Write-LogDebug "     ✓ Window positioned at => ($X, $Y) with size [${Width}x${Height}]" -Style Success
			return $true
		}
		else {
			if (Test-LogVerbose) {
				$errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
				Write-LogDebug "Failed to set window position (Error code: $errorCode)" -Style Warning
			}
			return $false
		}
	}
	catch {
		if (Test-LogVerbose) {
			Write-LogDebug "Failed to set window position: $_" -Style Error
		}
		return $false
	}
}
