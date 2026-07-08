function Get-MonitorInfo {
	<#
	.SYNOPSIS
		Gets information about connected monitors.

	.DESCRIPTION
		Retrieves information about all connected monitors including their dimensions,
		which helps in calculating zone positions for FancyZones.

	.PARAMETER Quiet
		Suppresses console output. Use this when you want to retrieve monitor info silently.

	.EXAMPLE
		Get-MonitorInfo

	.EXAMPLE
		Get-MonitorInfo -Quiet
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[switch]$Quiet
	)

	# Ensure Windows Forms is loaded (cached)
	Ensure-WindowsFormsLoaded

	# Get monitor information (cached)
	try {
		$screens = Get-CachedMonitors

		if ((Test-LogVerbose) -and -not $Quiet) {
			Write-LogTitle "Detecting Connected Monitors"
		}

		$monitors = @()
		$index = 1

		foreach ($screen in $screens) {
			$bounds = $screen.Bounds
			$workingArea = $screen.WorkingArea

			$monitor = [PSCustomObject]@{
				DeviceName     = $screen.DeviceName
				Left           = $bounds.Left
				Top            = $bounds.Top
				Right          = $bounds.Right
				Bottom         = $bounds.Bottom
				Width          = $bounds.Width
				Height         = $bounds.Height
				WorkAreaLeft   = $workingArea.Left
				WorkAreaTop    = $workingArea.Top
				WorkAreaRight  = $workingArea.Right
				WorkAreaBottom = $workingArea.Bottom
				WorkAreaWidth  = $workingArea.Width
				WorkAreaHeight = $workingArea.Height
				IsPrimary      = $screen.Primary
			}

			if ((Test-LogVerbose) -and -not $Quiet) {
				Write-LogDebug "Monitor $index $(if ($monitor.IsPrimary) { '[Primary]' })"
				Write-LogStep "  Device => $($monitor.DeviceName)" -NoLeadingNewline
				Write-LogStep "  Resolution => $($monitor.Width) x $($monitor.Height)" -NoLeadingNewline
				Write-LogStep "  Position => ($($monitor.Left), $($monitor.Top)) to ($($monitor.Right), $($monitor.Bottom))" -NoLeadingNewline
				Write-LogStep "  Work Area => $($monitor.WorkAreaWidth) x $($monitor.WorkAreaHeight)" -NoLeadingNewline
				Write-LogStep "  Work Area Position => ($($monitor.WorkAreaLeft), $($monitor.WorkAreaTop))" -NoLeadingNewline
			}

			$monitors += $monitor
			$index++
		}

		return $monitors
	}
	catch {
		Write-Error "Failed to get monitor information: $_"
		return @()
	}
}
