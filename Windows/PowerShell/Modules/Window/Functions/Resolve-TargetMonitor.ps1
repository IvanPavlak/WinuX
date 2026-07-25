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

		Note that a numeric index is POSITIONAL - it follows Get-MonitorInfo /
		Screen.AllScreens enumeration order, which is not guaranteed to match the numbering
		shown in Windows display settings and can change when displays are re-enumerated.
		Labels and device names are stable identifiers; prefer them when the target must
		survive a display reconfiguration.

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
		- Label        : display label for the resolved monitor (for example "Monitor2")
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
	$monitorLabel = $null

	# 1-based index into the enumeration order.
	$monitorIndex = 0
	if ([int]::TryParse($monitorInput, [ref]$monitorIndex)) {
		if ($monitorIndex -lt 1 -or $monitorIndex -gt $allMonitors.Count) {
			$result.ErrorMessage = "Error: Monitor index [$monitorIndex] is out of range. Available monitor indices: 1..$($allMonitors.Count)."
			return $result
		}
		$targetMonitor = $allMonitors[$monitorIndex - 1]
		$monitorLabel = "Monitor$monitorIndex"
	}

	# "Primary" tracks whichever monitor is currently primary.
	if (-not $targetMonitor -and $monitorInput -ieq 'Primary') {
		$targetMonitor = $allMonitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
		$monitorLabel = 'Primary'
	}

	# Standardized labels (Secondary, Monitor3, ...) matched through Get-MonitorSpecs geometry.
	if (-not $targetMonitor) {
		$monitorSpecs = Get-MonitorSpecs -MonitorInfo $allMonitors
		if ($monitorSpecs -and ($monitorSpecs.PSObject.Properties.Name -contains $monitorInput)) {
			$targetSpec = $monitorSpecs.$monitorInput
			$targetMonitor = $allMonitors | Where-Object {
				$_.Left -eq $targetSpec.X -and $_.Top -eq $targetSpec.Y -and
				$_.Width -eq $targetSpec.Width -and $_.Height -eq $targetSpec.Height
			} | Select-Object -First 1
			if ($targetMonitor) {
				$monitorLabel = $monitorInput
			}
		}
	}

	# Exact device name.
	if (-not $targetMonitor) {
		$targetMonitor = $allMonitors | Where-Object { $_.DeviceName -ieq $monitorInput } | Select-Object -First 1
		if ($targetMonitor) {
			$monitorLabel = $targetMonitor.DeviceName
		}
	}

	if (-not $targetMonitor) {
		$availableLabels = @('Primary')
		for ($i = 2; $i -le $allMonitors.Count; $i++) {
			$availableLabels += if ($i -eq 2) { 'Secondary' } else { "Monitor$i" }
		}
		$result.ErrorMessage = "Error: Could not resolve monitor [$Monitor]. Available labels: $($availableLabels -join ', ')."
		return $result
	}

	$result.Monitor = $targetMonitor
	$result.Label = $monitorLabel
	return $result
}
