function Get-MonitorDeviceIdentityMap {
	<#
	.SYNOPSIS
		Maps display device names to the EDID code and PnP instance path FancyZones keys its files by.

	.DESCRIPTION
		Enumerates the attached displays through EnumDisplayDevices (WindowModule.Native's
		GetMonitorDeviceInfo, compiled from WindowNative.cs) and returns two hashtables keyed by
		display name ("\\.\DISPLAY1"): Edid holds the monitor's EDID code (e.g. DELA1A8) and Instance
		its PnP instance path (e.g. 4&1CFDC60E&0&UID8262), both upper-cased. These are the "monitor"
		and "monitor-instance" fields FancyZones writes into applied-layouts.json and
		app-zone-history.json, so Apply-FancyZones uses them for its idempotency keys and for the
		targets of the file-based layout application. When the native type is not loaded or the
		enumeration fails both maps are empty, and callers fall back to matching by display name.

	.OUTPUTS
		PSCustomObject with Edid (hashtable) and Instance (hashtable).

	.EXAMPLE
		$identity = Get-MonitorDeviceIdentityMap
		$identity.Edid['\\.\DISPLAY1']      # DELA1A8
		$identity.Instance['\\.\DISPLAY1']  # 4&1CFDC60E&0&UID8262

	.NOTES
		The instance path only reaches EnumDisplayDevices with EDD_GET_DEVICE_INTERFACE_NAME; the
		device-class form of the ID carries none, in which case Instance stays empty for that display.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param()

	$edid = @{}
	$instance = @{}

	try {
		$deviceInfoList = [WindowModule.Native]::GetMonitorDeviceInfo()
		foreach ($devInfo in $deviceInfoList) {
			if ($devInfo.DisplayName -and $devInfo.EdidCode) {
				$edid[$devInfo.DisplayName] = $devInfo.EdidCode.ToUpper()
				# PnP instance path - unique per physical device, present in newer FancyZones
				# schemas; tells two identical monitors (same EDID) apart.
				if ($devInfo.MonitorInstance) {
					$instance[$devInfo.DisplayName] = $devInfo.MonitorInstance.ToUpper()
				}
			}
		}
	}
	catch {
		# Native type not loaded (fresh dot-source) or EnumDisplayDevices failed: empty maps, and
		# callers fall back to matching by display name.
		$edid = @{}
		$instance = @{}
	}

	return [PSCustomObject]@{
		Edid     = $edid
		Instance = $instance
	}
}
