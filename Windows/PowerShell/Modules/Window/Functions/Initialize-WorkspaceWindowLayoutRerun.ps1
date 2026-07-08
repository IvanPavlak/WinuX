function Initialize-WorkspaceWindowLayoutRerun {
	<#
	.SYNOPSIS
		Prepares workspace window layout state before opening a rerun shell.

	.DESCRIPTION
		Runs the workspace layout rerun preflight that used to live in ReRun-LastCommand.
		The Window module owns this behavior because it knows whether a retry should preserve
		the current FancyZones/virtual desktop state or reset it before a full layout rerun.

		For every rerun, it runs the live RPC preflight when Get-RpcRetryPolicy is available.
		In window-only retry mode, it preserves the existing FancyZones process, applied monitor
		layouts, virtual desktops, and caches. In full cleanup mode, it force-restarts FancyZones
		through Start-FancyZones, verifies startup has settled, resets virtual desktops, and clears
		FancyZones, monitor, and window caches.

	.PARAMETER WindowOnlyRetry
		Preserves current FancyZones, virtual desktop, and cache state for targeted window retries.

	.EXAMPLE
		Initialize-WorkspaceWindowLayoutRerun -WindowOnlyRetry
		# Runs RPC preflight and preserves current layout state for a targeted retry.

	.EXAMPLE
		Initialize-WorkspaceWindowLayoutRerun
		# Runs RPC preflight, restarts FancyZones, resets desktops, and clears layout caches.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[switch]$WindowOnlyRetry
	)

	if (Get-Command Get-RpcRetryPolicy -ErrorAction SilentlyContinue) {
		[void](Get-RpcRetryPolicy -OperationLabel "rerun" -Probe)
	}

	if ($WindowOnlyRetry) {
		Write-LogWarning "Window-only retry mode active: keeping current virtual desktops and FancyZones state."
		return $true
	}

	$fancyZonesReady = $true
	if (Get-Command Start-FancyZones -ErrorAction SilentlyContinue) {
		try {
			Write-LogWarning "Restarting FancyZones before workspace layout rerun..."
			$fancyZonesReady = Start-FancyZones -ForceRestart -MaxWaitSeconds 20

			# Perform one non-force verification pass to ensure startup has settled.
			if ($fancyZonesReady) {
				Start-Sleep -Milliseconds 350
				$fancyZonesReady = Start-FancyZones -MaxWaitSeconds 8
			}

			if ($fancyZonesReady) {
				Write-LogSuccess "FancyZones restart verified."
			}
			else {
				Write-LogWarning "Warning: FancyZones restart could not be verified before rerun."
			}
		}
		catch {
			$fancyZonesReady = $false
			Write-LogWarning "Warning: Failed to restart FancyZones before rerun: $($_.Exception.Message)"
		}
	}

	$desktopStateReady = $true
	try {
		if (Get-Command Remove-VirtualDesktops -ErrorAction SilentlyContinue) {
			Write-LogWarning "Resetting virtual desktops and caches for clean rerun..."
			$removeResult = Remove-VirtualDesktops -ErrorAction SilentlyContinue
			if ($removeResult -eq $false) {
				$desktopStateReady = $false
			}
		}

		if (Get-Command Clear-FancyZonesCache -ErrorAction SilentlyContinue) {
			Clear-FancyZonesCache
		}
		if (Get-Command Clear-MonitorCache -ErrorAction SilentlyContinue) {
			Clear-MonitorCache
		}
		if (Get-Command Clear-WindowCache -ErrorAction SilentlyContinue) {
			Clear-WindowCache
		}

		Write-LogSuccess "Desktop and cache state cleared for clean layout reapplication."
	}
	catch {
		$desktopStateReady = $false
		Write-LogWarning "Warning: Desktop/cache reset encountered an issue: $($_.Exception.Message)"
	}

	return ($fancyZonesReady -and $desktopStateReady)
}
