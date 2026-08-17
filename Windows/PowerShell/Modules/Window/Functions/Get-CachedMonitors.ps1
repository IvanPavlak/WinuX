function Get-CachedMonitors {
	<#
	.SYNOPSIS
		Returns cached monitor information from System.Windows.Forms.Screen.

	.DESCRIPTION
		Gets monitor/screen information from cache if still valid, otherwise
		refreshes from System.Windows.Forms.Screen.AllScreens. This reduces
		repeated calls to the Windows Forms API.

		The cache is invalidated by either of two signals: a display-topology change (see
		below) or the TTL expiring. Call Clear-MonitorCache to invalidate it explicitly.

	.OUTPUTS
		Array of System.Windows.Forms.Screen objects representing all monitors.

	.EXAMPLE
		$monitors = Get-CachedMonitors
		Gets all screen/monitor information.
	#>
	# Cheap display-topology fingerprint - monitor count plus the virtual-screen rectangle, two
	# GetSystemMetrics calls with no allocation.
	$getTopologyFingerprint = {
		try {
			$virtualScreen = [System.Windows.Forms.SystemInformation]::VirtualScreen
			$monitorCount = [System.Windows.Forms.SystemInformation]::MonitorCount
			return "$monitorCount|$($virtualScreen.X),$($virtualScreen.Y),$($virtualScreen.Width),$($virtualScreen.Height)"
		}
		catch {
			# Fingerprinting is an optimization on top of the TTL, never a requirement.
			return $null
		}
	}

	$now = [datetime]::Now
	$age = ($now - $script:MonitorCache.Timestamp).TotalSeconds

	# The fingerprint exists because monitor LABELS are derived from physical position
	# (Get-MonitorSpecs): serving a stale cache after the displays change hands out labels for
	# an arrangement that is gone, and a TTL alone only bounds how long that wrong answer
	# survives. It catches an attach, a detach, a resolution change and most rearrangements; a
	# swap that leaves both the count and the overall bounds identical still needs the TTL,
	# which is why the TTL is kept short rather than removed.
	#
	# Skipped until Windows Forms is loaded - which any cached entry already implies, since
	# nothing can populate the cache without loading Forms first - so validating the cache
	# never drags the assembly in on its own.
	$fingerprint = if ($script:WindowsFormsLoaded) { & $getTopologyFingerprint } else { $null }

	$topologyChanged = $null -ne $fingerprint -and
		$null -ne $script:MonitorCache.Fingerprint -and
		$fingerprint -ne $script:MonitorCache.Fingerprint

	if ($null -eq $script:MonitorCache.Monitors -or
		$age -gt $script:MonitorCache.MaxAgeSec -or
		$topologyChanged) {
		# Ensure Windows Forms is loaded (cached)
		Ensure-WindowsFormsLoaded
		$script:MonitorCache.Monitors = [System.Windows.Forms.Screen]::AllScreens
		$script:MonitorCache.Timestamp = $now
		# Re-read rather than reusing $fingerprint: the first refresh of a session computes it
		# before Forms is loaded, so $fingerprint is still $null at that point.
		$script:MonitorCache.Fingerprint = & $getTopologyFingerprint
	}
	elseif ($null -eq $script:MonitorCache.Fingerprint) {
		# Baseline a cache that was populated before Forms was available, so the next call has
		# something to compare against.
		$script:MonitorCache.Fingerprint = $fingerprint
	}

	return $script:MonitorCache.Monitors
}
