function Write-AppliedFancyZonesLayouts {
	<#
	.SYNOPSIS
		Writes zone layouts for virtual desktops straight into FancyZones' applied-layouts.json.

	.DESCRIPTION
		FancyZones records the layout applied to every (monitor, virtual desktop) pair in
		applied-layouts.json and watches that file: an external write makes it reload the file and
		re-initialize the work areas of the current desktop, and the work areas it creates later,
		when a desktop is switched to, read their entry from the reloaded data. Writing the entries
		for a workspace's desktops therefore applies the zone layouts to all of them at once, without
		switching to each desktop and injecting the Win+Ctrl+Alt+[Number] shortcut there.

		Each target names a monitor (EDID code and PnP instance path, as FancyZones records them), a
		virtual desktop GUID and a layout name from custom-layouts.json. The device block of the entry
		is cloned from an entry FancyZones itself wrote for that monitor - it carries the serial number
		and monitor number FancyZones matches its work areas against - so a monitor FancyZones has
		never written an entry for cannot be targeted and is reported as NoDeviceEntry. The
		applied-layout block is derived the way FancyZones derives it from a custom layout
		(CustomLayouts::GetLayout): type "custom", the grid's spacing settings, and the highest cell
		index + 1 as the zone count; a canvas contributes its zone count and sensitivity radius and
		takes FancyZones' defaults for the rest.

		A target whose entry already holds the wanted layout is reported AlreadyApplied and leaves the
		file alone unless -Force is given, in which case the file is rewritten anyway so that
		FancyZones reloads it. Every other entry in the file is preserved in place. The write is
		atomic - the content goes to a temporary file in the same directory that then replaces
		applied-layouts.json - and the file's last-write time is bumped afterwards, because the
		FancyZones watcher only wakes on last-write-time changes and a rename alone would go
		unnoticed. A file that cannot be parsed is never overwritten: FancyZones treats a malformed
		file as empty, so a broken write would wipe every layout it knows about.

		The function does not confirm that FancyZones picked the change up. Apply-FancyZones does
		that with Test-AppliedFancyZonesLayouts after a probe shortcut, and falls back to the
		desktop-switching shortcut pass for any desktop that does not verify.

	.PARAMETER Targets
		Objects (hashtables or PSCustomObjects) with Monitor (EDID code, e.g. DELA1A8),
		MonitorInstance (PnP instance path, e.g. 4&1cfdc60e&0&UID8262), VirtualDesktop (GUID, braces
		optional) and LayoutName (a name from custom-layouts.json). An optional Label is carried
		through to the result for logging.

	.PARAMETER Force
		Rewrite the file even when every target is already applied, so FancyZones reloads it.

	.PARAMETER AppliedLayoutsPath
		Path of applied-layouts.json. Defaults to the FancyZones data directory under %LOCALAPPDATA%.

	.PARAMETER CustomLayoutsPath
		Path of custom-layouts.json. Defaults to the FancyZones data directory under %LOCALAPPDATA%.

	.OUTPUTS
		PSCustomObject with Written (bool), WrittenAtUtc (the last-write time stamped on the file, or
		$null), Path, WrittenCount, AlreadyAppliedCount, UnresolvedCount, Error and Targets - one
		record per target with Monitor, MonitorInstance, VirtualDesktop, LayoutName, Uuid, Label and
		Status: Written, AlreadyApplied, NoDeviceEntry or UnknownLayout.

	.EXAMPLE
		$result = Write-AppliedFancyZonesLayouts -Targets @(
			@{ Monitor = 'DELA1A8'; MonitorInstance = '4&1cfdc60e&0&UID8262'; VirtualDesktop = '{413742B8-DC0B-4412-9D80-A2EAD2DE3829}'; LayoutName = 'Five' }
		)
		if ($result.Written) { Test-AppliedFancyZonesLayouts -Targets $result.Targets -WaitForWriteAfterUtc $result.WrittenAtUtc }

	.NOTES
		Only entries for the targets are touched; the entries FancyZones keeps for other monitors
		and desktops stay exactly where they were.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true)]
		[array]$Targets,

		[Parameter()]
		[switch]$Force,

		[Parameter()]
		[string]$AppliedLayoutsPath,

		[Parameter()]
		[string]$CustomLayoutsPath
	)

	$fancyZonesDirectory = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\FancyZones"
	if ([string]::IsNullOrWhiteSpace($AppliedLayoutsPath)) {
		$AppliedLayoutsPath = Join-Path $fancyZonesDirectory "applied-layouts.json"
	}
	if ([string]::IsNullOrWhiteSpace($CustomLayoutsPath)) {
		$CustomLayoutsPath = Join-Path $fancyZonesDirectory "custom-layouts.json"
	}

	$normalizeGuid = {
		param([string]$Value)
		$normalized = if ($null -ne $Value) { $Value.Trim().ToUpper() } else { '' }
		if ($normalized -and -not $normalized.StartsWith('{')) {
			$normalized = "{$normalized}"
		}
		return $normalized
	}

	$records = [System.Collections.Generic.List[object]]::new()
	$addRecord = {
		param($Target, [string]$Status, [string]$Uuid)
		$records.Add([PSCustomObject]@{
				Monitor         = [string]$Target.Monitor
				MonitorInstance = [string]$Target.MonitorInstance
				VirtualDesktop  = & $normalizeGuid ([string]$Target.VirtualDesktop)
				LayoutName      = [string]$Target.LayoutName
				Uuid            = $Uuid
				Label           = [string]$Target.Label
				Status          = $Status
			})
	}

	$finish = {
		param([bool]$Written, $WrittenAtUtc, [string]$ErrorMessage)
		$all = @($records.ToArray())
		return [PSCustomObject]@{
			Written             = $Written
			WrittenAtUtc        = $(if ($Written) { $WrittenAtUtc } else { $null })
			Path                = $AppliedLayoutsPath
			WrittenCount        = @($all | Where-Object { $_.Status -eq 'Written' }).Count
			AlreadyAppliedCount = @($all | Where-Object { $_.Status -eq 'AlreadyApplied' }).Count
			UnresolvedCount     = @($all | Where-Object { $_.Status -in @('NoDeviceEntry', 'UnknownLayout') }).Count
			Error               = $ErrorMessage
			Targets             = $all
		}
	}

	# A missing file means FancyZones has never written a device block we could clone; a file that
	# does not parse is never written over (FancyZones reads a malformed file as "no layouts").
	if (-not (Test-Path -LiteralPath $AppliedLayoutsPath)) {
		foreach ($target in $Targets) { & $addRecord $target 'NoDeviceEntry' $null }
		return & $finish $false $null $null
	}

	$entries = @()
	try {
		$document = Get-Content -LiteralPath $AppliedLayoutsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
		if ($document -and $document.'applied-layouts') {
			$entries = @($document.'applied-layouts')
		}
	}
	catch {
		Write-LogDebug "  applied-layouts.json could not be parsed - leaving it untouched: $($_.Exception.Message)" -Style Warning
		foreach ($target in $Targets) { & $addRecord $target 'NoDeviceEntry' $null }
		return & $finish $false $null "applied-layouts.json is not valid JSON: $($_.Exception.Message)"
	}

	$layoutsByName = @{}
	$customLayouts = Get-CachedFancyZonesLayouts -LayoutsJsonPath $CustomLayoutsPath
	if ($customLayouts -and $customLayouts.'custom-layouts') {
		foreach ($customLayout in @($customLayouts.'custom-layouts')) {
			if ($customLayout.name -and $customLayout.uuid) {
				$layoutsByName[[string]$customLayout.name] = $customLayout
			}
		}
	}

	$resolveCustomLayout = {
		param([string]$Name)
		if ($layoutsByName.ContainsKey($Name)) { return $layoutsByName[$Name] }
		foreach ($key in $layoutsByName.Keys) {
			if ($key -ieq $Name) { return $layoutsByName[$key] }
		}
		return $null
	}

	# Mirrors CustomLayouts::GetLayout in FancyZones: type "custom", the grid's spacing settings and
	# highest cell index + 1 as the zone count; a canvas contributes its zone count and sensitivity
	# radius and takes FancyZones' defaults (spacing shown, 16 px) for the rest.
	$convertToAppliedLayout = {
		param($CustomLayout)
		$info = $CustomLayout.info
		$showSpacing = $true
		$spacing = 16
		$zoneCount = 0
		$sensitivityRadius = 20

		if ($info) {
			if ($null -ne $info.'sensitivity-radius') { $sensitivityRadius = [int]$info.'sensitivity-radius' }

			if ([string]$CustomLayout.type -eq 'canvas') {
				$zoneCount = @($info.zones).Count
			}
			else {
				if ($null -ne $info.'show-spacing') { $showSpacing = [bool]$info.'show-spacing' }
				if ($null -ne $info.spacing) { $spacing = [int]$info.spacing }

				$highestCell = -1
				foreach ($row in @($info.'cell-child-map')) {
					foreach ($cell in @($row)) {
						if ([int]$cell -gt $highestCell) { $highestCell = [int]$cell }
					}
				}
				$zoneCount = $highestCell + 1
			}
		}

		return [PSCustomObject]([ordered]@{
				'uuid'               = & $normalizeGuid ([string]$CustomLayout.uuid)
				'type'               = 'custom'
				'show-spacing'       = $showSpacing
				'spacing'            = $spacing
				'zone-count'         = $zoneCount
				'sensitivity-radius' = $sensitivityRadius
			})
	}

	# String comparisons below are PowerShell's case-insensitive -eq: FancyZones writes the PnP
	# instance in lower-case hex while EnumDisplayDevices consumers tend to upper-case it.
	$entryMatches = {
		param($Entry, [string]$Monitor, [string]$Instance, [string]$DesktopGuid)
		$device = $Entry.device
		if (-not $device) { return $false }
		if ([string]$device.monitor -ne $Monitor) { return $false }
		if ([string]$device.'monitor-instance' -ne $Instance) { return $false }
		if ($DesktopGuid) {
			return ((& $normalizeGuid ([string]$device.'virtual-desktop')) -eq $DesktopGuid)
		}
		return $true
	}

	$working = [System.Collections.Generic.List[object]]::new()
	foreach ($entry in $entries) { $working.Add($entry) }
	$changedCount = 0
	$resolvedCount = 0

	foreach ($target in $Targets) {
		$monitor = [string]$target.Monitor
		$instance = [string]$target.MonitorInstance
		$desktopGuid = & $normalizeGuid ([string]$target.VirtualDesktop)
		$layoutName = [string]$target.LayoutName

		$customLayout = & $resolveCustomLayout $layoutName
		if (-not $customLayout) {
			& $addRecord $target 'UnknownLayout' $null
			continue
		}
		$appliedLayout = & $convertToAppliedLayout $customLayout
		$uuid = $appliedLayout.uuid

		$deviceEntryIndexes = @()
		for ($index = 0; $index -lt $working.Count; $index++) {
			if (& $entryMatches $working[$index] $monitor $instance $null) { $deviceEntryIndexes += $index }
		}
		if ($deviceEntryIndexes.Count -eq 0) {
			& $addRecord $target 'NoDeviceEntry' $uuid
			continue
		}
		$resolvedCount++

		$existingIndex = -1
		foreach ($index in $deviceEntryIndexes) {
			if (& $entryMatches $working[$index] $monitor $instance $desktopGuid) {
				$existingIndex = $index
				break
			}
		}

		if ($existingIndex -ge 0 -and -not $Force) {
			$existingUuid = & $normalizeGuid ([string]$working[$existingIndex].'applied-layout'.uuid)
			if ($existingUuid -eq $uuid) {
				& $addRecord $target 'AlreadyApplied' $uuid
				continue
			}
		}

		# Clone the device block from the entry for this very desktop when there is one, else from
		# any entry of the monitor - serial number and monitor number are what FancyZones matches
		# its live work area against, so they must be exactly what it wrote itself.
		$sourceIndex = if ($existingIndex -ge 0) { $existingIndex } else { $deviceEntryIndexes[0] }
		$sourceDevice = $working[$sourceIndex].device
		$device = [PSCustomObject]([ordered]@{
				'monitor'          = [string]$sourceDevice.monitor
				'monitor-instance' = [string]$sourceDevice.'monitor-instance'
				'serial-number'    = [string]$sourceDevice.'serial-number'
				'monitor-number'   = $(if ($null -ne $sourceDevice.'monitor-number') { [int]$sourceDevice.'monitor-number' } else { 0 })
				'virtual-desktop'  = $desktopGuid
			})
		$newEntry = [PSCustomObject]([ordered]@{
				'device'         = $device
				'applied-layout' = $appliedLayout
			})

		if ($existingIndex -ge 0) {
			$working[$existingIndex] = $newEntry
		}
		else {
			$working.Add($newEntry)
		}
		$changedCount++
		& $addRecord $target 'Written' $uuid
	}

	if ($changedCount -eq 0 -and -not ($Force -and $resolvedCount -gt 0)) {
		return & $finish $false $null $null
	}

	# Same shape FancyZones writes: one compact line, the array under "applied-layouts".
	$json = [PSCustomObject]@{ 'applied-layouts' = [object[]]$working.ToArray() } | ConvertTo-Json -Depth 10 -Compress
	$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
	$tempPath = "$AppliedLayoutsPath.$PID.tmp"
	$writtenAtUtc = $null

	try {
		[System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)

		# ReplaceFile is atomic: a reader sees either the old file or the new one, never a torn
		# write. It fails while another process holds the file open; FancyZones holds it only for
		# the length of a read, so one short retry covers that, then an in-place write is the
		# last resort.
		$replaced = $false
		for ($attempt = 0; $attempt -lt 2 -and -not $replaced; $attempt++) {
			try {
				[System.IO.File]::Replace($tempPath, $AppliedLayoutsPath, $null)
				$replaced = $true
			}
			catch {
				Start-Sleep -Milliseconds 50
			}
		}
		if (-not $replaced) {
			[System.IO.File]::WriteAllText($AppliedLayoutsPath, $json, $utf8NoBom)
			Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
		}

		# The FancyZones file watcher (a WIL folder change reader on LastWriteTime) compares the
		# file's last-write time with the one it saw last; a rename does not change that time,
		# so stamp it explicitly. This is also the mark Test-AppliedFancyZonesLayouts waits past.
		$writtenAtUtc = [datetime]::UtcNow
		[System.IO.File]::SetLastWriteTimeUtc($AppliedLayoutsPath, $writtenAtUtc)
	}
	catch {
		if (Test-Path -LiteralPath $tempPath) {
			Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
		}
		Write-LogDebug "  Could not write applied-layouts.json: $($_.Exception.Message)" -Style Warning
		return & $finish $false $null $_.Exception.Message
	}

	# The module cache now describes a stale file.
	if ($script:AppliedLayoutsCache) {
		$script:AppliedLayoutsCache.Data = $null
		$script:AppliedLayoutsCache.Timestamp = [datetime]::MinValue
	}

	if (Test-LogVerbose) {
		Write-LogDebug "  applied-layouts.json written: $changedCount entr$(if ($changedCount -eq 1) { 'y' } else { 'ies' }) for $($Targets.Count) target(s)" -Style Success
	}

	return & $finish $true $writtenAtUtc $null
}
