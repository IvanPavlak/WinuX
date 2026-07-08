function Get-CachedMonitors {
	<#
	.SYNOPSIS
		Returns cached monitor information from System.Windows.Forms.Screen.

	.DESCRIPTION
		Gets monitor/screen information from cache if still valid, otherwise
		refreshes from System.Windows.Forms.Screen.AllScreens. This reduces
		repeated calls to the Windows Forms API.

	.OUTPUTS
		Array of System.Windows.Forms.Screen objects representing all monitors.

	.EXAMPLE
		$monitors = Get-CachedMonitors
		Gets all screen/monitor information.
	#>
	$now = [datetime]::Now
	$age = ($now - $script:MonitorCache.Timestamp).TotalSeconds

	if ($null -eq $script:MonitorCache.Monitors -or $age -gt $script:MonitorCache.MaxAgeSec) {
		# Ensure Windows Forms is loaded (cached)
		Ensure-WindowsFormsLoaded
		$script:MonitorCache.Monitors = [System.Windows.Forms.Screen]::AllScreens
		$script:MonitorCache.Timestamp = $now
	}

	return $script:MonitorCache.Monitors
}
