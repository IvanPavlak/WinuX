function Get-AppliedFancyZonesState {
	<#
	.SYNOPSIS
		Reads the currently applied FancyZones layout state from disk.

	.DESCRIPTION
		Reads and caches the FancyZones applied-layouts.json file, which records the
		layout currently applied to each monitor on each virtual desktop. Returns a
		lookup hashtable keyed by "{MonitorId}:{VirtualDesktopGUID}" with layout
		UUID values.

		MonitorId is the FancyZones 'monitor' field - either an EDID hardware code
		(e.g., "LEN8ABC", "DELA1A8") or a display path (e.g., "\\.\DISPLAY1").

		Used by Apply-FancyZones for idempotency - skipping keyboard shortcut sends
		when a monitor already has the correct layout applied.

	.PARAMETER Force
		Forces a re-read of the file even if cached data exists.

	.OUTPUTS
		Hashtable mapping "{MonitorId}:{VirtualDesktopGUID}" to "{LayoutUUID}",
		or $null if the file cannot be read or parsed.

	.EXAMPLE
		$state = Get-AppliedFancyZonesState
		$key = "LEN8ABC:{CF6C2856-0D59-466D-AA7F-E6DF85C6034C}"
		if ($state[$key] -eq "{9D07C01E-877C-4B03-B2D9-3DCC0C1E961F}") { "Already applied" }

	.EXAMPLE
		# Force re-read after applying layouts
		$freshState = Get-AppliedFancyZonesState -Force

	.NOTES
		The applied-layouts.json file is written by FancyZones in real-time whenever
		a layout is applied (via keyboard shortcut, drag-drop, or editor).
		Cache TTL is kept short (10s) since the file changes during layout application.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[switch]$Force
	)

	$appliedLayoutsPath = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones\applied-layouts.json"

	if (-not (Test-Path $appliedLayoutsPath)) {
		return $null
	}

	# Check cache validity
	$now = [datetime]::Now
	$age = ($now - $script:AppliedLayoutsCache.Timestamp).TotalSeconds

	if (-not $Force -and
		$null -ne $script:AppliedLayoutsCache.Data -and
		$age -lt $script:AppliedLayoutsCache.MaxAgeSec) {
		return $script:AppliedLayoutsCache.Data
	}

	try {
		$rawData = Get-Content $appliedLayoutsPath -Raw | ConvertFrom-Json

		if (-not $rawData.'applied-layouts') {
			return $null
		}

		# Build lookup: "{monitor}:{VirtualDesktopGUID}" → "{LayoutUUID}"
		# The monitor field is either an EDID code (e.g., "LEN8ABC") or display path ("\\.\DISPLAY1").
		# Newer FancyZones schemas also record the PnP 'monitor-instance', which is unique per
		# physical device even when two identical monitors share one EDID - an additional
		# instance-qualified key "{monitor}|{instance}:{GUID}" is stored so consumers with
		# instance data can match unambiguously (the EDID-only key collides on duplicates,
		# last write wins - kept for backward compatibility and instance-less callers).
		$lookup = @{}

		foreach ($entry in $rawData.'applied-layouts') {
			$device = $entry.device
			$layout = $entry.'applied-layout'

			if ($device -and $layout) {
				$monitor = $device.monitor
				$monitorInstance = $device.'monitor-instance'
				$vdGuid = $device.'virtual-desktop'
				$layoutUuid = $layout.uuid

				if ($monitor -and $vdGuid -and $layoutUuid) {
					$key = "$($monitor.ToUpper()):$($vdGuid.ToUpper())"
					$lookup[$key] = $layoutUuid.ToUpper()

					if ($monitorInstance) {
						$qualifiedKey = "$($monitor.ToUpper())|$($monitorInstance.ToUpper()):$($vdGuid.ToUpper())"
						$lookup[$qualifiedKey] = $layoutUuid.ToUpper()
					}
				}
			}
		}

		# Update cache
		$script:AppliedLayoutsCache.Data = $lookup
		$script:AppliedLayoutsCache.Timestamp = $now

		return $lookup
	}
	catch {
		Write-Verbose "Failed to read applied-layouts.json: $_"
		return $null
	}
}
