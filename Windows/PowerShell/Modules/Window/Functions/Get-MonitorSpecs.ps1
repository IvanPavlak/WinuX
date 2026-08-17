function Get-MonitorSpecs {
	<#
	.SYNOPSIS
		Gets monitor specifications in a format suitable for layout configurations.

	.DESCRIPTION
		Returns monitor information with standardized labels (Primary, Secondary, etc.)
		that can be used directly in layout configuration files. This makes layouts
		portable across different display configurations.

		LABEL ORDERING: the primary display is always "Primary". The remaining displays are
		labeled "Secondary", "Monitor3", "Monitor4", ... in PHYSICAL order - sorted by Left,
		then Top, then DeviceName - never in Get-MonitorInfo / Screen.AllScreens enumeration
		order, which is neither spatial nor stable across a display re-enumeration. A label
		therefore identifies a POSITION in the current arrangement, not a specific panel:
		rearranging displays in Windows display settings reassigns the labels, and layout
		files that name them follow the new arrangement. Use Resolve-MonitorLabel to convert
		between a label and its 0-based ordinal.

		Each spec carries two geometries: X/Y/Width/Height are the full monitor bounds
		(used to IDENTIFY physical monitors - Apply-FancyZones and layout files match on
		bounds), while WorkX/WorkY/WorkWidth/WorkHeight are the work area (bounds minus
		taskbar). FancyZones lays its zones over the WORK AREA, so all zone-geometry math
		must use the Work* fields. The two are identical when the taskbar is auto-hidden.

	.PARAMETER AsHashtable
		Returns the result as a hashtable instead of PSCustomObject for easier use
		in layout configuration files.

	.PARAMETER MonitorInfo
		Optional pre-fetched monitor information from Get-MonitorInfo. If provided,
		skips the monitor detection call for better performance.

	.EXAMPLE
		# Get monitor specs for use in code
		$monitors = Get-MonitorSpecs
		$primary = $monitors.Primary

	.EXAMPLE
		# Use cached monitor info to avoid redundant calls
		$monitorInfo = Get-MonitorInfo
		$specs = Get-MonitorSpecs -MonitorInfo $monitorInfo

	.EXAMPLE
		# Get monitor specs as hashtable for layout files
		$monitors = Get-MonitorSpecs -AsHashtable

	.EXAMPLE
		# Use in layout configuration
		$zone = Get-FancyZone -LayoutName "One" -ZoneName "Left" `
			-MonitorX $monitors.Primary.X -MonitorY $monitors.Primary.Y `
			-MonitorWidth $monitors.Primary.Width -MonitorHeight $monitors.Primary.Height
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[switch]$AsHashtable,

		[Parameter()]
		[array]$MonitorInfo
	)

	try {
		# Use provided monitor info or fetch it
		if ($MonitorInfo) {
			$allMonitors = $MonitorInfo
		}
		else {
			$allMonitors = Get-MonitorInfo
		}

		if (-not $allMonitors -or $allMonitors.Count -eq 0) {
			Write-Error "No monitors detected"
			return $null
		}

		# Create a standardized monitor spec object
		$monitorSpecs = @{}

		# Builds one spec from a Get-MonitorInfo record. Work* fields fall back to the
		# full bounds when the record carries no work-area data (older callers, test
		# fixtures) so zone math degrades to the previous bounds-based behavior instead
		# of failing on $null coordinates.
		$newMonitorSpec = {
			param($monitor)
			@{
				X          = $monitor.Left
				Y          = $monitor.Top
				Width      = $monitor.Width
				Height     = $monitor.Height
				WorkX      = if ($null -ne $monitor.WorkAreaLeft) { $monitor.WorkAreaLeft } else { $monitor.Left }
				WorkY      = if ($null -ne $monitor.WorkAreaTop) { $monitor.WorkAreaTop } else { $monitor.Top }
				WorkWidth  = if ($monitor.WorkAreaWidth) { $monitor.WorkAreaWidth } else { $monitor.Width }
				WorkHeight = if ($monitor.WorkAreaHeight) { $monitor.WorkAreaHeight } else { $monitor.Height }
				DeviceName = $monitor.DeviceName
			}
		}

		# Find primary monitor
		$primaryMonitor = $allMonitors | Where-Object { $_.IsPrimary } | Select-Object -First 1

		if ($primaryMonitor) {
			$monitorSpecs["Primary"] = & $newMonitorSpec $primaryMonitor
		}

		# Add the non-primary monitors in a deterministic PHYSICAL order.
		#
		# Get-MonitorInfo / Screen.AllScreens enumeration order is neither spatial nor stable:
		# the non-primary display can sort first, and the order can change on monitor
		# sleep/wake, a DisplayPort link drop, a GPU driver reload or a dock/undock. With two
		# displays there is exactly one non-primary monitor, so "Secondary" was unambiguous
		# whatever the order and the instability was invisible. With three or more, which
		# physical panel became "Secondary" versus "Monitor3" was arbitrary and could swap
		# between runs, silently retargeting every layout entry that named them.
		#
		# Sorting by (Left, Top) makes the labels a function of the physical arrangement alone:
		# left to right, then top to bottom for displays stacked at the same X. DeviceName
		# breaks the remaining tie so mirrored displays - which report identical bounds - still
		# get a fixed order rather than an arbitrary one.
		$secondaryMonitors = @(
			$allMonitors |
				Where-Object { -not $_.IsPrimary } |
				Sort-Object -Property `
					@{ Expression = { [int]$_.Left } },
					@{ Expression = { [int]$_.Top } },
					@{ Expression = { [string]$_.DeviceName } }
		)

		# Ordinal 0 is reserved for the primary display, so the spatially-first non-primary
		# monitor is ordinal 1 ("Secondary").
		$index = 1

		foreach ($monitor in $secondaryMonitors) {
			$label = Resolve-MonitorLabel -Index $index

			$monitorSpecs[$label] = & $newMonitorSpec $monitor

			$index++
		}

		# Return as hashtable or custom object
		if ($AsHashtable) {
			return $monitorSpecs
		}
		else {
			# Convert to PSCustomObject for easier property access
			$result = [PSCustomObject]@{}
			foreach ($key in $monitorSpecs.Keys) {
				$result | Add-Member -NotePropertyName $key -NotePropertyValue ([PSCustomObject]$monitorSpecs[$key])
			}
			return $result
		}
	}
	catch {
		Write-Error "Failed to get monitor specifications: $_"
		return $null
	}
}
