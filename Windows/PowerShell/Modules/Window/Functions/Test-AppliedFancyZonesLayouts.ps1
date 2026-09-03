function Test-AppliedFancyZonesLayouts {
	<#
	.SYNOPSIS
		Verifies that applied-layouts.json holds the wanted layout for each monitor/desktop target,
		optionally after waiting for FancyZones to rewrite the file.

	.DESCRIPTION
		Reads FancyZones' applied-layouts.json and checks, per target, that exactly one entry exists
		for the monitor (EDID code and PnP instance path) on the virtual desktop and that it carries
		the expected layout uuid. A target is Verified on a match, Missing when no entry exists,
		Mismatch when the entry names another layout, and Duplicate when more than one entry claims
		the same monitor and desktop - the sign that an entry written from outside used a device
		block FancyZones does not recognize as its own, so FancyZones added a second one.

		With -WaitForWriteAfterUtc the function first polls the file's last-write time until it is
		later than the given stamp (or -TimeoutMs runs out) and reports the outcome as SaveObserved.
		That is the confirmation step of the file-based layout application: after
		Write-AppliedFancyZonesLayouts stamps the file, Apply-FancyZones sends one layout shortcut
		on the current desktop, which makes FancyZones save its whole in-memory layout map back to
		the file. If FancyZones had reloaded the written file, every written entry survives that save
		and verifies here; if it had not, the save reverts them and the targets read as Missing or
		Mismatch, so the caller falls back to the shortcut pass for those desktops.

	.PARAMETER Targets
		Objects with Monitor, MonitorInstance, VirtualDesktop (GUID, braces optional) and Uuid (the
		expected layout uuid) - for example the Targets records Write-AppliedFancyZonesLayouts
		returns. Label is carried through when present.

	.PARAMETER WaitForWriteAfterUtc
		When given, wait until the file's last-write time (UTC) is later than this before reading.

	.PARAMETER TimeoutMs
		How long to wait for that later write. Default 750 ms.

	.PARAMETER PollIntervalMs
		Delay between polls of the last-write time. Default 25 ms; 0 spins (tests).

	.PARAMETER AppliedLayoutsPath
		Path of applied-layouts.json. Defaults to the FancyZones data directory under %LOCALAPPDATA%.

	.OUTPUTS
		PSCustomObject with SaveObserved ($true/$false when -WaitForWriteAfterUtc was given, else
		$null), Readable (the file parsed), AllVerified, VerifiedCount and Targets - one record per
		target with Monitor, MonitorInstance, VirtualDesktop, Uuid, Label, Status (Verified, Missing,
		Mismatch, Duplicate, Unreadable) and ActualUuid.

	.EXAMPLE
		$check = Test-AppliedFancyZonesLayouts -Targets $written.Targets -WaitForWriteAfterUtc $written.WrittenAtUtc
		if ($check.SaveObserved -and $check.AllVerified) { "FancyZones holds every layout" }
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true)]
		[array]$Targets,

		[Parameter()]
		[datetime]$WaitForWriteAfterUtc,

		[Parameter()]
		[ValidateRange(0, [int]::MaxValue)]
		[int]$TimeoutMs = 750,

		[Parameter()]
		[ValidateRange(0, [int]::MaxValue)]
		[int]$PollIntervalMs = 25,

		[Parameter()]
		[string]$AppliedLayoutsPath
	)

	if ([string]::IsNullOrWhiteSpace($AppliedLayoutsPath)) {
		$AppliedLayoutsPath = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones\applied-layouts.json"
	}

	$normalizeGuid = {
		param([string]$Value)
		$normalized = if ($null -ne $Value) { $Value.Trim().ToUpper() } else { '' }
		if ($normalized -and -not $normalized.StartsWith('{')) {
			$normalized = "{$normalized}"
		}
		return $normalized
	}

	# PSBoundParameters rather than a null check: PowerShell unwraps nullable parameters, so an
	# unset [datetime] would read as 0001-01-01 and every file would look "written after" it.
	$saveObserved = $null
	if ($PSBoundParameters.ContainsKey('WaitForWriteAfterUtc')) {
		$saveObserved = $false
		$clock = [System.Diagnostics.Stopwatch]::StartNew()
		while ($true) {
			$stamp = try { [System.IO.File]::GetLastWriteTimeUtc($AppliedLayoutsPath) } catch { [datetime]::MinValue }
			if ($stamp -gt $WaitForWriteAfterUtc) {
				$saveObserved = $true
				break
			}
			if ($clock.ElapsedMilliseconds -ge $TimeoutMs) {
				break
			}
			if ($PollIntervalMs -gt 0) {
				Start-Sleep -Milliseconds $PollIntervalMs
			}
		}
	}

	# FancyZones may still be mid-write when its last-write time moves; a parse failure is retried
	# a few times before the file is reported unreadable.
	$entries = @()
	$readable = $false
	for ($attempt = 0; $attempt -lt 4 -and -not $readable; $attempt++) {
		if (-not (Test-Path -LiteralPath $AppliedLayoutsPath)) {
			break
		}
		try {
			$document = Get-Content -LiteralPath $AppliedLayoutsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
			if ($document -and $document.'applied-layouts') {
				$entries = @($document.'applied-layouts')
			}
			$readable = $true
		}
		catch {
			Start-Sleep -Milliseconds 25
		}
	}

	$records = foreach ($target in $Targets) {
		$monitor = [string]$target.Monitor
		$instance = [string]$target.MonitorInstance
		$desktopGuid = & $normalizeGuid ([string]$target.VirtualDesktop)
		$expectedUuid = & $normalizeGuid ([string]$target.Uuid)

		$status = 'Unreadable'
		$actualUuid = $null
		if ($readable) {
			# Case-insensitive -eq on purpose: FancyZones writes the PnP instance in lower-case hex.
			$matchingEntries = @($entries | Where-Object {
					$_.device -and
					([string]$_.device.monitor -eq $monitor) -and
					([string]$_.device.'monitor-instance' -eq $instance) -and
					((& $normalizeGuid ([string]$_.device.'virtual-desktop')) -eq $desktopGuid)
				})

			if ($matchingEntries.Count -eq 0) {
				$status = 'Missing'
			}
			elseif ($matchingEntries.Count -gt 1) {
				$status = 'Duplicate'
				$actualUuid = (@($matchingEntries | ForEach-Object { & $normalizeGuid ([string]$_.'applied-layout'.uuid) }) -join ', ')
			}
			else {
				$actualUuid = & $normalizeGuid ([string]$matchingEntries[0].'applied-layout'.uuid)
				$status = if ($actualUuid -eq $expectedUuid) { 'Verified' } else { 'Mismatch' }
			}
		}

		[PSCustomObject]@{
			Monitor         = $monitor
			MonitorInstance = $instance
			VirtualDesktop  = $desktopGuid
			Uuid            = $expectedUuid
			Label           = [string]$target.Label
			Status          = $status
			ActualUuid      = $actualUuid
		}
	}
	$records = @($records)

	$verifiedCount = @($records | Where-Object { $_.Status -eq 'Verified' }).Count

	return [PSCustomObject]@{
		SaveObserved  = $saveObserved
		Readable      = $readable
		AllVerified   = ($records.Count -gt 0 -and $verifiedCount -eq $records.Count)
		VerifiedCount = $verifiedCount
		Targets       = $records
	}
}
