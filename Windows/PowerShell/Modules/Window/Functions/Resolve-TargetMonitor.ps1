function Resolve-TargetMonitor {
	<#
	.SYNOPSIS
		Resolves a monitor specifier (index, label, or device name) to a monitor object.

	.DESCRIPTION
		Shared monitor-targeting resolver for the placement functions. Accepts the three
		forms callers expose through their own -Monitor parameter:
		- 1-based monitor index following Get-MonitorInfo order (for example: 1, 2)
		- standardized labels from Get-MonitorSpecs (Primary, Secondary, Monitor3, ...)
		- exact monitor device name (for example: \\.\DISPLAY1)

		Extracted from Move-Windows so Move-Windows and Center-Windows resolve -Monitor
		through one set of matching rules instead of each carrying its own copy. This
		function writes no console output: it returns the resolved monitor together with a
		ready-to-log ErrorMessage, leaving logging and control flow (abort, return, or
		fall back) to the caller.

		The three forms are not equally stable, and the difference matters most with three or
		more displays:
		- A numeric index follows Get-MonitorInfo / Screen.AllScreens ENUMERATION order, which
		  is not guaranteed to match the numbering in Windows display settings and can change
		  when displays are re-enumerated (monitor sleep/wake, a DisplayPort link drop, a GPU
		  driver reload, a dock/undock). Least stable form - avoid it in configuration.
		- A label follows PHYSICAL arrangement (see Get-MonitorSpecs), so it survives a
		  re-enumeration but not an actual rearrangement of the displays.
		- A device name is the closest thing to a fixed identity. Prefer it when the target
		  must survive a display reconfiguration.

		Whichever form resolves, the returned Label is always the standardized label of the
		monitor that was resolved, so a log line naming it agrees with what a layout file
		would call that panel.

	.PARAMETER Monitor
		The monitor specifier: 1-based index, label, or device name. Empty, whitespace-only,
		or absent input resolves to "no targeting requested" - Monitor and ErrorMessage are
		both $null and Requested is $false.

	.PARAMETER MonitorInfo
		Monitor objects from Get-MonitorInfo. When omitted, Get-MonitorInfo -Quiet is called.
		Pass an already-retrieved set to avoid enumerating the monitors twice.

	.OUTPUTS
		PSCustomObject with:
		- Monitor      : the resolved monitor object, or $null when unresolved / not requested
		- Label        : standardized label of the resolved monitor ("Primary", "Secondary",
		                 "Monitor3", ...), or its device name when no label matches
		- ErrorMessage : why resolution failed, or $null on success / no request
		- Requested    : $true when a non-empty specifier was supplied

	.EXAMPLE
		$resolved = Resolve-TargetMonitor -Monitor "2" -MonitorInfo $monitors
		if (-not $resolved.Monitor) { Write-LogError $resolved.ErrorMessage; return }

	.EXAMPLE
		Resolve-TargetMonitor -Monitor "Primary"
		Resolves the currently primary monitor, enumerating monitors on demand.

	.EXAMPLE
		(Resolve-TargetMonitor -Monitor "").Requested
		# => False (no monitor targeting requested)
	#>
	[CmdletBinding()]
	param (
		[Parameter(Position = 0)]
		[AllowEmptyString()]
		[AllowNull()]
		[string]$Monitor,

		[Parameter()]
		[AllowNull()]
		[object[]]$MonitorInfo
	)

	$result = [PSCustomObject]@{
		Monitor      = $null
		Label        = $null
		ErrorMessage = $null
		Requested    = $false
	}

	if ([string]::IsNullOrWhiteSpace($Monitor)) {
		return $result
	}

	$result.Requested = $true

	$allMonitors = @($MonitorInfo | Where-Object { $null -ne $_ })
	if ($allMonitors.Count -eq 0) {
		$allMonitors = @(Get-MonitorInfo -Quiet)
	}

	if ($allMonitors.Count -eq 0) {
		$result.ErrorMessage = "Error: Could not detect any monitors for -Monitor targeting!"
		return $result
	}

	$monitorInput = $Monitor.Trim()
	$targetMonitor = $null

	# Resolved once for every path, not just the label path: the returned Label is always the
	# standardized label of whichever monitor was resolved, so an index or a device name reports
	# the same name a layout file would use for that panel. Reporting the raw input instead used
	# to make "-Monitor 3" log "Monitor3" even when the third ENUMERATED monitor is not the panel
	# that Get-MonitorSpecs calls "Monitor3" - the two orders are unrelated.
	$monitorSpecs = Get-MonitorSpecs -MonitorInfo $allMonitors

	# 1-based index into the enumeration order.
	$monitorIndex = 0
	if ([int]::TryParse($monitorInput, [ref]$monitorIndex)) {
		if ($monitorIndex -lt 1 -or $monitorIndex -gt $allMonitors.Count) {
			$result.ErrorMessage = "Error: Monitor index [$monitorIndex] is out of range. Available monitor indices: 1..$($allMonitors.Count)."
			return $result
		}
		$targetMonitor = $allMonitors[$monitorIndex - 1]
	}

	# "Primary" tracks whichever monitor is currently primary.
	if (-not $targetMonitor -and $monitorInput -ieq 'Primary') {
		$targetMonitor = $allMonitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
	}

	# Standardized labels (Secondary, Monitor3, ...) matched through Get-MonitorSpecs.
	if (-not $targetMonitor -and $monitorSpecs -and ($monitorSpecs.PSObject.Properties.Name -contains $monitorInput)) {
		$targetMonitor = Find-MonitorMatchingSpec -Monitors $allMonitors -Spec $monitorSpecs.$monitorInput
	}

	# Exact device name.
	if (-not $targetMonitor) {
		$targetMonitor = $allMonitors | Where-Object { $_.DeviceName -ieq $monitorInput } | Select-Object -First 1
	}

	if (-not $targetMonitor) {
		$availableLabels = @()
		for ($i = 0; $i -lt $allMonitors.Count; $i++) {
			$availableLabels += Resolve-MonitorLabel -Index $i
		}
		$result.ErrorMessage = "Error: Could not resolve monitor [$Monitor]. Available labels: $($availableLabels -join ', ')."
		return $result
	}

	$result.Monitor = $targetMonitor
	$result.Label = Get-MonitorSpecLabel -MonitorSpecs $monitorSpecs -Monitor $targetMonitor
	return $result
}

function Find-MonitorMatchingSpec {
	<#
	.SYNOPSIS
		Finds the monitor backing a Get-MonitorSpecs spec (internal helper).

	.DESCRIPTION
		Matches on DeviceName first and falls back to bounds. DeviceName is checked first
		because bounds alone are ambiguous when displays are mirrored - they report identical
		bounds, so a bounds-only match returns whichever monitor happens to be enumerated
		first. Called by Resolve-TargetMonitor and Get-MonitorSpecLabel; not intended for
		direct use.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[AllowNull()]
		[object[]]$Monitors,

		[Parameter(Mandatory = $true)]
		[AllowNull()]
		[object]$Spec
	)

	if (-not $Spec -or -not $Monitors) { return $null }

	if ($Spec.DeviceName) {
		$byDeviceName = $Monitors | Where-Object { $_.DeviceName -ieq $Spec.DeviceName } | Select-Object -First 1
		if ($byDeviceName) { return $byDeviceName }
	}

	return $Monitors | Where-Object {
		$_.Left -eq $Spec.X -and $_.Top -eq $Spec.Y -and
		$_.Width -eq $Spec.Width -and $_.Height -eq $Spec.Height
	} | Select-Object -First 1
}

function Get-MonitorSpecLabel {
	<#
	.SYNOPSIS
		Returns the standardized label of a monitor (internal helper).

	.DESCRIPTION
		Reverse lookup through a Get-MonitorSpecs result: given a monitor object, returns the
		label ("Primary", "Secondary", "Monitor3", ...) that layout files use for it. Falls
		back to the monitor's device name when no spec matches, so the caller always has
		something meaningful to log. Called by Resolve-TargetMonitor; not intended for direct
		use.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[AllowNull()]
		[object]$MonitorSpecs,

		[Parameter(Mandatory = $true)]
		[AllowNull()]
		[object]$Monitor
	)

	if (-not $Monitor) { return $null }

	if ($MonitorSpecs) {
		# Walk labels in Primary, Secondary, Monitor3, ... order so the answer does not depend
		# on hashtable/property enumeration order.
		$orderedLabels = @(
			$MonitorSpecs.PSObject.Properties.Name | Sort-Object { Resolve-MonitorLabel -Label $_ }
		)

		foreach ($label in $orderedLabels) {
			$matchedMonitor = Find-MonitorMatchingSpec -Monitors @($Monitor) -Spec $MonitorSpecs.$label
			if ($matchedMonitor) { return $label }
		}
	}

	return $Monitor.DeviceName
}
