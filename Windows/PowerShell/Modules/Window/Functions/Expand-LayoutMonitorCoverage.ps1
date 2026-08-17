function Expand-LayoutMonitorCoverage {
	<#
	.SYNOPSIS
		Extends a layout's Monitors section to cover every attached monitor.

	.DESCRIPTION
		Layout files are authored for the display setup their author had. Any attached monitor
		a file does not define gets no FancyZones layout at all: Apply-FancyZones iterates the
		Monitors section, so an undefined monitor is never visited and keeps whatever zone
		layout it happened to have. This function fills those gaps in place, cloning the
		per-desktop layouts of the first defined monitor as a template.

		It runs for EVERY workspace. The equivalent block used to live inside
		Set-WorkspaceWindowLayout's SimpleLayoutWorkspaces branch, which made Fullscreen and
		Empty the only two workspaces that adapted to a newly attached display - attach a third
		monitor and open any normal workspace and that monitor was silently under-served.

		Only the Monitors section is extended, never the Layout array. An auto-added monitor
		therefore gets a zone layout but no window assignments: nothing is moved onto it, and
		nothing already targeted elsewhere changes. Monitors the file defines are never
		modified.

		Set AutoExtendMonitors = $false at the top level of a layout file to opt that layout
		out and leave undefined monitors alone.

	.PARAMETER Config
		The parsed layout configuration (from Import-PowerShellDataFile). Its Monitors
		hashtable is modified IN PLACE.

	.PARAMETER MonitorInfo
		Monitor objects from Get-MonitorInfo. When omitted, Get-MonitorInfo -Quiet is called.
		Pass an already-retrieved set to avoid enumerating the monitors twice.

	.OUTPUTS
		String array of the monitor labels that were added - empty when the layout already
		covered every attached monitor, opted out, or carried no usable template.

	.EXAMPLE
		$config = Import-PowerShellDataFile -Path $layoutPath
		$added = Expand-LayoutMonitorCoverage -Config $config -MonitorInfo $monitors
		if ($added.Count -gt 0) { Write-LogDebug "Auto-added [$($added -join ', ')]" }

	.EXAMPLE
		# A layout that must leave undefined monitors untouched:
		#   @{
		#       AutoExtendMonitors = $false
		#       Monitors = @{ Primary = @{ VirtualDesktopLayouts = @{ 1 = "One" } } }
		#       Layout   = @( ... )
		#   }
		Expand-LayoutMonitorCoverage -Config $config
		# => @() - nothing added
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[AllowNull()]
		[hashtable]$Config,

		[Parameter()]
		[AllowNull()]
		[object[]]$MonitorInfo
	)

	$addedLabels = @()

	if (-not $Config -or -not $Config.Monitors) {
		return $addedLabels
	}

	# An absent key means enabled - extending is the documented default, and an explicit
	# AutoExtendMonitors = $false is the only way to opt a layout out.
	if ($Config.ContainsKey('AutoExtendMonitors') -and -not $Config.AutoExtendMonitors) {
		return $addedLabels
	}

	$allMonitors = @($MonitorInfo | Where-Object { $null -ne $_ })
	if ($allMonitors.Count -eq 0) {
		$allMonitors = @(Get-MonitorInfo -Quiet)
	}

	if ($allMonitors.Count -eq 0) {
		return $addedLabels
	}

	$monitorSpecs = Get-MonitorSpecs -MonitorInfo $allMonitors -AsHashtable
	if (-not $monitorSpecs) {
		return $addedLabels
	}

	# Template = the first monitor the file defines in LABEL order (Primary, Secondary,
	# Monitor3, ...) rather than hashtable order, so which monitor gets cloned does not depend
	# on Import-PowerShellDataFile's key ordering.
	$templateLabel = @($Config.Monitors.Keys | Sort-Object { Resolve-MonitorLabel -Label $_ }) | Select-Object -First 1
	if (-not $templateLabel) {
		return $addedLabels
	}

	$templateMonitor = $Config.Monitors[$templateLabel]
	if (-not $templateMonitor -or -not $templateMonitor.VirtualDesktopLayouts) {
		return $addedLabels
	}

	foreach ($label in @($monitorSpecs.Keys | Sort-Object { Resolve-MonitorLabel -Label $_ })) {
		if ($Config.Monitors.ContainsKey($label)) {
			continue
		}

		$Config.Monitors[$label] = @{
			VirtualDesktopLayouts = @{}
		}

		foreach ($desktopKey in $templateMonitor.VirtualDesktopLayouts.Keys) {
			$Config.Monitors[$label].VirtualDesktopLayouts[$desktopKey] = $templateMonitor.VirtualDesktopLayouts[$desktopKey]
		}

		$addedLabels += $label
	}

	return $addedLabels
}
