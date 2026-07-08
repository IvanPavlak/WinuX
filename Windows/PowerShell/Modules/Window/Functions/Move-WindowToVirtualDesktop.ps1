function Move-WindowToVirtualDesktop {
	<#
	.SYNOPSIS
		Moves a window to a specific virtual desktop.

	.DESCRIPTION
		Moves a window (identified by its handle) to the specified virtual desktop number.
		Requires the VirtualDesktop module or uses COM automation as fallback.
		Note: This function uses 0-based indexing internally. Layout files use 1-based
		indexing which is converted before calling this function.

	.PARAMETER WindowHandle
		The window handle (HWND) to move.

	.PARAMETER DesktopNumber
		The desktop number (0-based index) to move the window to.

	.EXAMPLE
		$handle = (Get-WindowHandle -ProcessName "chrome")[0].Handle
		Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber 0 # Moves to the first desktop

	.EXAMPLE
		Move-WindowToVirtualDesktop -WindowHandle $handle -DesktopNumber 1 # Moves to the second desktop
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[IntPtr]$WindowHandle,

		[Parameter(Mandatory = $true)]
		[int]$DesktopNumber
	)

	# Use cached VirtualDesktop module loader
	if (Import-VirtualDesktopModule) {
		try {

			# Get desktop count to validate target
			$desktopCount = Get-DesktopCount

			# Diagnostic output
			Write-Verbose "Found $desktopCount virtual desktop(s)"

			if ($DesktopNumber -lt 0 -or $DesktopNumber -ge $desktopCount) {
				Write-Error "Desktop number $DesktopNumber is out of range. Available desktops: 0-$($desktopCount - 1)"
				return $false
			}

			# Get the target desktop directly by its index (0-based)
			$targetDesktopObj = Get-Desktop -Index $DesktopNumber

			if (-not $targetDesktopObj) {
				Write-Error "Could not find virtual desktop with index $DesktopNumber"
				return $false
			}

			# Move window using native desktop object
			Write-Verbose "Moving window (handle: 0x$($WindowHandle.ToString('X'))) to desktop object"

			$moveError = $null
			try {
				Move-Window -Desktop $targetDesktopObj -Hwnd $WindowHandle.ToInt64()
			}
			catch {
				# Capture the error but don't fail yet - we'll verify if the move actually succeeded
				$moveError = $_
			}

			# Verify the move
			Start-Sleep -Milliseconds $script:WindowModuleDelays.VirtualDesktopMs

			$verifyIndex = -1
			$verifyError = $null
			try {
				$verifyDesktop = Get-DesktopFromWindow -Hwnd $WindowHandle.ToInt64()
				$verifyIndex = Get-DesktopIndex $verifyDesktop
			}
			catch {
				# TYPE_E_ELEMENTNOTFOUND often occurs during verification even when move succeeded
				$verifyError = $_
			}

			# Check if move succeeded despite potential error (TYPE_E_ELEMENTNOTFOUND often occurs even on success)
			if ($verifyIndex -eq $DesktopNumber) {
				if (Test-LogVerbose) {
					Write-Verbose "Window is now on desktop index $verifyIndex"
					Write-LogDebug "Moved window to virtual desktop [$DesktopNumber]" -Style Success
				}
				return $true
			}
			elseif ($moveError -or $verifyError) {
				# Move or verification had an error - report it only in debug mode to avoid noise
				# TYPE_E_ELEMENTNOTFOUND is common and often doesn't indicate a real failure
				if (Test-LogVerbose) {
					$errorToReport = if ($moveError) { $moveError } else { $verifyError }
					Write-Warning "Move-WindowToVirtualDesktop encountered error (may be transient): $errorToReport"
				}
				return $false
			}
			else {
				# No error but verification failed
				if (Test-LogVerbose) {
					Write-Warning "Window move could not be verified. Expected desktop $DesktopNumber, found $verifyIndex"
				}
				return $false
			}
		}
		catch {
			# Suppress TYPE_E_ELEMENTNOTFOUND and similar transient errors in normal mode
			if (Test-LogVerbose) {
				Write-Warning "Move-WindowToVirtualDesktop encountered error: $_"
			}
			return $false
		}
	}
	else {
		Write-Warning "VirtualDesktop module not found. To install it, run:"
		Write-Warning "Install-Module -Name VirtualDesktop -Scope CurrentUser"
		Write-Host "`nAlternatively, you can install it via: https://github.com/MScholtes/PSVirtualDesktop"
		return $false
	}
}
