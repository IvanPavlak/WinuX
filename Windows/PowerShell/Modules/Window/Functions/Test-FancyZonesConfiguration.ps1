function Test-FancyZonesConfiguration {
	<#
	.SYNOPSIS
		Validates the FancyZones configuration triad against each other.

	.DESCRIPTION
		Arbitrary layouts, zones, and spacing are supported in custom-layouts.json, which
		makes drift between the four places that must agree the main way a workspace open
		can misplace windows or apply the wrong layout. This validates:

		1. Every layout in custom-layouts.json is internally consistent:
		   - grid: rows/columns match their percentage arrays, each percentage axis sums
		     to exactly 10000, cell-child-map is rows x columns and its zone indices form
		     a contiguous 0..N-1 set, spacing is not negative.
		   - canvas: ref-width/ref-height are positive, every zone has positive
		     width/height (zones extending beyond the ref rect only warn).
		2. $Configuration.ZoneNameMappings agrees with custom-layouts.json: every mapped
		   layout exists, and every mapped zone index is within the layout's derived zone
		   count. Layouts without a mappings entry (and zone indices without a name) are
		   warnings, not errors - they only matter once a layout .psd1 references them.
		3. $Configuration.LayoutNumbers is applyable: values 0-9, unique, and every name
		   exists in custom-layouts.json.
		4. layout-hotkeys.json agrees with both: every hotkey uuid exists in
		   custom-layouts.json, and for each LayoutNumbers entry the hotkey with that
		   number points at that layout's uuid - otherwise Apply-FancyZones would apply
		   the WRONG layout via its Win+Ctrl+Alt+number shortcut.

		Errors carry the affected layout name (or $null for cross-file problems such as
		hotkey mismatches) so callers can scope their reaction: Set-WorkspaceWindowLayout
		aborts an open only when an error touches a layout that workspace references, or
		when the error is global.

	.PARAMETER CustomLayoutsPath
		Optional path to custom-layouts.json. Defaults to the repository file
		(Get-FancyZonesLayoutsPath).

	.PARAMETER LayoutHotkeysPath
		Optional path to layout-hotkeys.json. Defaults to the repository file
		(Get-FancyZonesLayoutsPath -File LayoutHotkeys).

	.PARAMETER Silent
		Suppresses per-finding logging; the result object is returned either way.

	.EXAMPLE
		Test-FancyZonesConfiguration
		Validates the repository FancyZones configuration and logs every finding.

	.EXAMPLE
		$result = Test-FancyZonesConfiguration -Silent
		if (-not $result.Valid) { $result.Errors | ForEach-Object { $_.Message } }

	.OUTPUTS
		[pscustomobject] with:
		- Valid    : $true when no errors were found (warnings do not affect validity)
		- Errors   : array of @{ Layout; Message } objects (Layout $null = global)
		- Warnings : array of @{ Layout; Message } objects
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string]$CustomLayoutsPath,

		[Parameter()]
		[string]$LayoutHotkeysPath,

		[Parameter()]
		[switch]$Silent
	)

	$errors = [System.Collections.Generic.List[object]]::new()
	$warnings = [System.Collections.Generic.List[object]]::new()

	$addError = {
		param($layout, $message)
		$errors.Add([PSCustomObject]@{ Layout = $layout; Message = $message })
		if (-not $Silent) { Write-LogError " [Test-FancyZonesConfiguration] $message" -NoLeadingNewline }
	}
	$addWarning = {
		param($layout, $message)
		$warnings.Add([PSCustomObject]@{ Layout = $layout; Message = $message })
		if (-not $Silent) { Write-LogWarning " [Test-FancyZonesConfiguration] $message" -NoLeadingNewline }
	}

	if (-not $CustomLayoutsPath) { $CustomLayoutsPath = Get-FancyZonesLayoutsPath }
	if (-not $LayoutHotkeysPath) { $LayoutHotkeysPath = Get-FancyZonesLayoutsPath -File LayoutHotkeys }

	# ------------------------------------------------------------------
	# Load custom-layouts.json and derive each layout's zone count
	# ------------------------------------------------------------------
	$layoutZoneCounts = @{}
	$layoutUuids = @{}

	if (-not (Test-Path $CustomLayoutsPath)) {
		& $addError $null "Custom layouts file not found: $CustomLayoutsPath"
	}
	else {
		$customLayouts = Get-CachedFancyZonesLayouts -LayoutsJsonPath $CustomLayoutsPath
		if ($null -eq $customLayouts -or $null -eq $customLayouts.'custom-layouts') {
			& $addError $null "Failed to load custom layouts JSON from: $CustomLayoutsPath"
		}
		else {
			foreach ($layout in @($customLayouts.'custom-layouts')) {
				$layoutName = $layout.name
				$layoutUuids[$layoutName] = $layout.uuid

				switch ($layout.type) {
					"grid" {
						$rows = [int]$layout.info.rows
						$columns = [int]$layout.info.columns
						$rowPercentages = @($layout.info.'rows-percentage')
						$columnPercentages = @($layout.info.'columns-percentage')
						$cellChildMap = @($layout.info.'cell-child-map')
						$layoutValid = $true

						if ($rows -lt 1 -or $columns -lt 1) {
							& $addError $layoutName "Layout '$layoutName': rows ($rows) and columns ($columns) must both be at least 1"
							$layoutValid = $false
						}
						if ($rowPercentages.Count -ne $rows) {
							& $addError $layoutName "Layout '$layoutName': rows-percentage has $($rowPercentages.Count) entries but rows is $rows"
							$layoutValid = $false
						}
						if ($columnPercentages.Count -ne $columns) {
							& $addError $layoutName "Layout '$layoutName': columns-percentage has $($columnPercentages.Count) entries but columns is $columns"
							$layoutValid = $false
						}
						if ($cellChildMap.Count -ne $rows) {
							& $addError $layoutName "Layout '$layoutName': cell-child-map has $($cellChildMap.Count) rows but rows is $rows"
							$layoutValid = $false
						}
						else {
							for ($row = 0; $row -lt $cellChildMap.Count; $row++) {
								if (@($cellChildMap[$row]).Count -ne $columns) {
									& $addError $layoutName "Layout '$layoutName': cell-child-map row $row has $(@($cellChildMap[$row]).Count) entries but columns is $columns"
									$layoutValid = $false
								}
							}
						}

						# The prefix-sum zone math lands the last edge at sum * extent / 10000,
						# so a sum that is not exactly 10000 silently shrinks or overflows the
						# last row/column instead of failing - reject it here.
						$rowSum = 0
						foreach ($percentage in $rowPercentages) { $rowSum += [int]$percentage }
						if ($rowPercentages.Count -gt 0 -and $rowSum -ne 10000) {
							& $addError $layoutName "Layout '$layoutName': rows-percentage sums to $rowSum, must be exactly 10000"
							$layoutValid = $false
						}
						$columnSum = 0
						foreach ($percentage in $columnPercentages) { $columnSum += [int]$percentage }
						if ($columnPercentages.Count -gt 0 -and $columnSum -ne 10000) {
							& $addError $layoutName "Layout '$layoutName': columns-percentage sums to $columnSum, must be exactly 10000"
							$layoutValid = $false
						}

						if ($layout.info.'show-spacing' -and [int]$layout.info.spacing -lt 0) {
							& $addError $layoutName "Layout '$layoutName': spacing ($([int]$layout.info.spacing)) must not be negative"
							$layoutValid = $false
						}

						if ($layoutValid) {
							$zoneIndices = @{}
							foreach ($mapRow in $cellChildMap) {
								foreach ($cell in @($mapRow)) {
									$zoneIndices[[int]$cell] = $true
								}
							}
							$zoneCount = $zoneIndices.Count

							$isContiguous = $true
							for ($index = 0; $index -lt $zoneCount; $index++) {
								if (-not $zoneIndices.ContainsKey($index)) { $isContiguous = $false; break }
							}
							if (-not $isContiguous) {
								& $addError $layoutName "Layout '$layoutName': cell-child-map zone indices [$(($zoneIndices.Keys | Sort-Object) -join ', ')] are not a contiguous 0..$($zoneCount - 1) set"
							}
							else {
								$layoutZoneCounts[$layoutName] = $zoneCount
							}
						}
					}
					"canvas" {
						$refWidth = [int]$layout.info.'ref-width'
						$refHeight = [int]$layout.info.'ref-height'
						$canvasZones = @($layout.info.zones)
						$layoutValid = $true

						if ($refWidth -le 0 -or $refHeight -le 0) {
							& $addError $layoutName "Layout '$layoutName': ref-width ($refWidth) and ref-height ($refHeight) must both be positive"
							$layoutValid = $false
						}
						if ($canvasZones.Count -eq 0) {
							& $addError $layoutName "Layout '$layoutName': canvas layout defines no zones"
							$layoutValid = $false
						}

						for ($index = 0; $index -lt $canvasZones.Count; $index++) {
							$zone = $canvasZones[$index]
							if ([int]$zone.width -le 0 -or [int]$zone.height -le 0) {
								& $addError $layoutName "Layout '$layoutName': canvas zone $index has non-positive size ($([int]$zone.width)x$([int]$zone.height))"
								$layoutValid = $false
							}
							elseif ($refWidth -gt 0 -and $refHeight -gt 0 -and
								([int]$zone.X + [int]$zone.width -gt $refWidth -or [int]$zone.Y + [int]$zone.height -gt $refHeight)) {
								& $addWarning $layoutName "Layout '$layoutName': canvas zone $index extends beyond the ref rect (${refWidth}x${refHeight})"
							}
						}

						if ($layoutValid) {
							$layoutZoneCounts[$layoutName] = $canvasZones.Count
						}
					}
					default {
						& $addWarning $layoutName "Layout '$layoutName': type '$($layout.type)' is not supported (only grid and canvas) - it cannot be used in layout .psd1 files"
					}
				}
			}
		}
	}

	# ------------------------------------------------------------------
	# ZoneNameMappings <-> custom-layouts.json
	# ------------------------------------------------------------------
	$zoneNameMappings = $global:Configuration.ZoneNameMappings
	if ($zoneNameMappings -and $layoutUuids.Count -gt 0) {
		foreach ($mappedLayout in $zoneNameMappings.Keys) {
			if (-not $layoutUuids.ContainsKey($mappedLayout)) {
				& $addError $mappedLayout "ZoneNameMappings entry '$mappedLayout' has no layout in custom-layouts.json - available layouts: $(($layoutUuids.Keys | Sort-Object) -join ', ')"
				continue
			}
			if (-not $layoutZoneCounts.ContainsKey($mappedLayout)) {
				# Layout exists but was itself invalid or unsupported - already reported above.
				continue
			}

			$zoneCount = $layoutZoneCounts[$mappedLayout]
			$namedIndices = @{}
			foreach ($zoneName in $zoneNameMappings[$mappedLayout].Keys) {
				$zoneIndex = [int]$zoneNameMappings[$mappedLayout][$zoneName]
				$namedIndices[$zoneIndex] = $true
				if ($zoneIndex -lt 0 -or $zoneIndex -ge $zoneCount) {
					& $addError $mappedLayout "Layout '$mappedLayout': zone name '$zoneName' maps to index $zoneIndex but the layout defines $zoneCount zones (0-$($zoneCount - 1)) - check ZoneNameMappings against custom-layouts.json"
				}
			}
			for ($index = 0; $index -lt $zoneCount; $index++) {
				if (-not $namedIndices.ContainsKey($index)) {
					& $addWarning $mappedLayout "Layout '$mappedLayout': zone index $index has no name in ZoneNameMappings - layout .psd1 files cannot reference it"
				}
			}
		}

		foreach ($jsonLayout in $layoutZoneCounts.Keys) {
			if (-not $zoneNameMappings.ContainsKey($jsonLayout)) {
				& $addWarning $jsonLayout "Layout '$jsonLayout' has no ZoneNameMappings entry - layout .psd1 files cannot reference its zones by name"
			}
		}
	}

	# ------------------------------------------------------------------
	# LayoutNumbers (hotkey slots)
	# ------------------------------------------------------------------
	$layoutNumbers = $global:Configuration.LayoutNumbers
	if ($layoutNumbers -and $layoutUuids.Count -gt 0) {
		$usedNumbers = @{}
		foreach ($layoutName in $layoutNumbers.Keys) {
			$number = [int]$layoutNumbers[$layoutName]
			if ($number -lt 0 -or $number -gt 9) {
				& $addError $null "LayoutNumbers: '$layoutName' is assigned $number - Apply-FancyZones only supports hotkeys 0-9"
			}
			elseif ($usedNumbers.ContainsKey($number)) {
				& $addError $null "LayoutNumbers: '$layoutName' and '$($usedNumbers[$number])' are both assigned hotkey $number"
			}
			else {
				$usedNumbers[$number] = $layoutName
			}
			if (-not $layoutUuids.ContainsKey($layoutName)) {
				& $addError $null "LayoutNumbers entry '$layoutName' has no layout in custom-layouts.json - available layouts: $(($layoutUuids.Keys | Sort-Object) -join ', ')"
			}
		}
	}

	# ------------------------------------------------------------------
	# layout-hotkeys.json <-> LayoutNumbers <-> custom-layouts.json
	# ------------------------------------------------------------------
	if ($layoutUuids.Count -gt 0) {
		if (-not (Test-Path $LayoutHotkeysPath)) {
			& $addError $null "Layout hotkeys file not found: $LayoutHotkeysPath"
		}
		else {
			$hotkeyEntries = $null
			try {
				$hotkeyEntries = (Get-Content $LayoutHotkeysPath -Raw | ConvertFrom-Json).'layout-hotkeys'
			}
			catch {
				& $addError $null "Failed to parse layout hotkeys JSON from: $LayoutHotkeysPath => $_"
			}

			if ($null -ne $hotkeyEntries) {
				$uuidsInJson = @{}
				foreach ($uuid in $layoutUuids.Values) { $uuidsInJson[$uuid] = $true }

				$hotkeyByNumber = @{}
				foreach ($hotkeyEntry in @($hotkeyEntries)) {
					$hotkeyByNumber[[int]$hotkeyEntry.key] = $hotkeyEntry.'layout-id'
					if (-not $uuidsInJson.ContainsKey($hotkeyEntry.'layout-id')) {
						& $addError $null "layout-hotkeys.json: hotkey $([int]$hotkeyEntry.key) points at uuid $($hotkeyEntry.'layout-id') which does not exist in custom-layouts.json"
					}
				}

				if ($layoutNumbers) {
					foreach ($layoutName in $layoutNumbers.Keys) {
						if (-not $layoutUuids.ContainsKey($layoutName)) { continue }
						$number = [int]$layoutNumbers[$layoutName]
						if ($number -lt 0 -or $number -gt 9) { continue }

						if (-not $hotkeyByNumber.ContainsKey($number)) {
							& $addError $null "layout-hotkeys.json: no entry for hotkey $number, but LayoutNumbers assigns it to '$layoutName' - Apply-FancyZones would send a dead shortcut"
						}
						elseif ($hotkeyByNumber[$number] -ne $layoutUuids[$layoutName]) {
							& $addError $null "layout-hotkeys.json: hotkey $number points at uuid $($hotkeyByNumber[$number]) but LayoutNumbers assigns it to '$layoutName' ($($layoutUuids[$layoutName])) - Apply-FancyZones would apply the WRONG layout"
						}
					}
				}
			}
		}
	}

	$isValid = ($errors.Count -eq 0)
	if (-not $Silent) {
		if ($isValid) {
			Write-LogDebug " [Test-FancyZonesConfiguration] FancyZones configuration is consistent ($($layoutZoneCounts.Count) usable layout(s), $($warnings.Count) warning(s))" -Style Success
		}
		else {
			Write-LogDebug " [Test-FancyZonesConfiguration] Found $($errors.Count) error(s) and $($warnings.Count) warning(s)" -Style Warning
		}
	}

	return [PSCustomObject]@{
		Valid    = $isValid
		Errors   = @($errors)
		Warnings = @($warnings)
	}
}
