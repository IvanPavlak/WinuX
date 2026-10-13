function Merge-LayoutProjectOverrides {
	<#
	.SYNOPSIS
		Applies a layout file's ProjectOverrides for the selected project(s).

	.DESCRIPTION
		A layout file may end with a ProjectOverrides block - project variants of ONE workspace's
		layout, kept in the same file:

			ProjectOverrides = @{
				"<project scope>" = @{
					Monitors = @{ Primary = @{ VirtualDesktopLayouts = @{ 2 = "One" } } }
					Layout   = @( <layout entries> )
				}
			}

		When a covered project is selected, the block is merged into a COPY of the loaded layout
		data before anything else uses it:

		  - Monitors merges key by key: only the listed desktops change their zone layout.
		  - The override's Layout entries REPLACE every base entry on the same desktop and monitor,
		    and are ADDED on a desktop and monitor the base does not use. The desktop-and-monitor
		    pair is the unit because a desktop's zone layout decides which zones exist there.
		  - A key may cover several projects ("A/B"). Several selected projects apply in selection
		    order; on the same desktop and monitor the later one wins.
		  - Clearing a desktop and monitor without a replacement is not supported.

		Validation runs over EVERY override block, selected or not, so a typo surfaces on any open:
		an empty key or a project token that is not a ProjectActions name, a block that is not a
		hashtable or has a key other than Monitors and Layout, a Monitors value that is not a
		hashtable, an override entry without DesktopNumber or Monitor, and an override entry with a
		Zone (and no Layout) whose desktop and monitor have no zone layout, or whose Zone does not
		exist in the zone layout they end up with (the override's Monitors applied over the base),
		are errors. Blocks with errors are not applied. A ProjectOverrides value that is not a
		hashtable is one error and nothing is applied.

		The input is never modified. Without a ProjectOverrides block, or when no selected project
		is covered, the result's Config is the input itself.

	.PARAMETER Config
		The layout data as Import-PowerShellDataFile returned it (Monitors, Layout, optional
		ProjectOverrides).

	.PARAMETER Project
		The selected project(s), in selection order.

	.PARAMETER ProjectNames
		The valid project tokens. Defaults to the ProjectActions names of the loaded configuration.

	.PARAMETER ZoneNameMappings
		Zone names per FancyZones layout, used to check that override zones exist. Defaults to
		ZoneNameMappings of the loaded configuration; zones are not checked when it is empty.

	.OUTPUTS
		[pscustomobject] with Config (the layout data to use), Applied (the override keys applied,
		in order), Variants (every override key) and Errors (one message per problem).

	.EXAMPLE
		$layout = Import-PowerShellDataFile -Path $layoutPath
		$merged = Merge-LayoutProjectOverrides -Config $layout -Project 'MyProject'
		$merged.Config.Layout
		# The base layout with MyProject's desktop/monitor entries swapped in
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[hashtable]$Config,

		[Parameter(Position = 1)]
		[AllowNull()]
		[AllowEmptyCollection()]
		[string[]]$Project,

		[Parameter()]
		[AllowNull()]
		[string[]]$ProjectNames,

		[Parameter()]
		[AllowNull()]
		[System.Collections.IDictionary]$ZoneNameMappings
	)

	$result = [PSCustomObject]@{
		Config   = $Config
		Applied  = @()
		Variants = @()
		Errors   = @()
	}

	$overrides = $Config['ProjectOverrides']
	if ($null -eq $overrides) { return $result }

	$errors = [System.Collections.Generic.List[string]]::new()
	if (-not ($overrides -is [System.Collections.IDictionary])) {
		$errors.Add("ProjectOverrides must be a hashtable of project scope => @{ Monitors = @{ ... }; Layout = @( ... ) }")
		$result.Errors = $errors.ToArray()
		return $result
	}

	if (-not $PSBoundParameters.ContainsKey('ProjectNames')) {
		$ProjectNames = @(Get-OrderedNames (Get-ConfigSetting -Path 'ProjectActions'))
	}
	if (-not $PSBoundParameters.ContainsKey('ZoneNameMappings')) {
		$ZoneNameMappings = Get-ConfigSetting -Path 'ZoneNameMappings' -Default @{}
	}
	$knownProjects = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($projectName in @($ProjectNames)) { if ($projectName) { [void]$knownProjects.Add($projectName) } }

	$copyDeep = {
		param($Value)
		if ($Value -is [System.Collections.IDictionary]) {
			$copy = @{}
			foreach ($key in $Value.Keys) { $copy[$key] = & $copyDeep $Value[$key] }
			return $copy
		}
		if (($Value -is [System.Collections.IList]) -and -not ($Value -is [string])) {
			$items = @(foreach ($item in $Value) { , (& $copyDeep $item) })
			return , $items
		}
		return $Value
	}

	# The zone layout a desktop/monitor pair ends up with: the override's Monitors over the base.
	$zoneLayoutOf = {
		param([System.Collections.IDictionary]$BaseMonitors, $OverrideMonitors, [string]$Monitor, $Desktop)
		foreach ($monitors in @($OverrideMonitors, $BaseMonitors)) {
			if (-not ($monitors -is [System.Collections.IDictionary])) { continue }
			$monitorConfig = $monitors[$Monitor]
			if ($monitorConfig -is [System.Collections.IDictionary] -and $monitorConfig.VirtualDesktopLayouts -is [System.Collections.IDictionary]) {
				foreach ($desktopKey in $monitorConfig.VirtualDesktopLayouts.Keys) {
					if ([int]$desktopKey -eq [int]$Desktop) { return [string]$monitorConfig.VirtualDesktopLayouts[$desktopKey] }
				}
			}
		}
		return $null
	}

	# Validate every block.
	$validKeys = [System.Collections.Generic.List[string]]::new()
	$keyTokens = @{}
	foreach ($overrideKey in $overrides.Keys) {
		$keyText = [string]$overrideKey
		$blockErrors = [System.Collections.Generic.List[string]]::new()
		$tokens = @(($keyText -split '/') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
		if ($tokens.Count -eq 0) { $blockErrors.Add("ProjectOverrides has an empty project key") }
		foreach ($token in $tokens) {
			if (-not $knownProjects.Contains($token)) {
				$blockErrors.Add("ProjectOverrides [$keyText] - unknown project [$token] (not a ProjectActions name)")
			}
		}

		$block = $overrides[$overrideKey]
		if (-not ($block -is [System.Collections.IDictionary])) {
			$blockErrors.Add("ProjectOverrides [$keyText] must be a hashtable with Monitors and/or Layout")
		}
		else {
			foreach ($blockKey in $block.Keys) {
				if (@('Monitors', 'Layout') -notcontains [string]$blockKey) {
					$blockErrors.Add("ProjectOverrides [$keyText] has an unknown key [$blockKey] - an override takes Monitors and Layout")
				}
			}
			if ($null -ne $block['Monitors'] -and -not ($block['Monitors'] -is [System.Collections.IDictionary])) {
				$blockErrors.Add("ProjectOverrides [$keyText].Monitors must be a hashtable like the file's Monitors section")
			}
			foreach ($entry in @($block['Layout'])) {
				if ($null -eq $entry) { continue }
				$label = "ProjectOverrides [$keyText] entry [$($entry.ProcessName)$(if ($entry.WindowTitle) { " - $($entry.WindowTitle)" })]"
				if ($null -eq $entry.DesktopNumber -or -not ($entry.Monitor -is [string]) -or [string]::IsNullOrWhiteSpace($entry.Monitor)) {
					$blockErrors.Add("$label needs DesktopNumber and a Monitor label - an override replaces a desktop and monitor")
					continue
				}
				if (-not $entry.Zone -or $entry.Layout) { continue }
				$zoneLayout = & $zoneLayoutOf $Config['Monitors'] $block['Monitors'] $entry.Monitor $entry.DesktopNumber
				if (-not $zoneLayout) {
					$blockErrors.Add("$label - no zone layout for Monitor [$($entry.Monitor)] desktop $($entry.DesktopNumber) in the base Monitors or the override's")
					continue
				}
				if ($ZoneNameMappings -is [System.Collections.IDictionary] -and $ZoneNameMappings.Count -gt 0) {
					$zoneNames = $ZoneNameMappings[$zoneLayout]
					if ($zoneNames -is [System.Collections.IDictionary] -and -not @($zoneNames.Keys | Where-Object { [string]$_ -ieq [string]$entry.Zone })) {
						$blockErrors.Add("$label - zone [$($entry.Zone)] does not exist in layout [$zoneLayout] (Monitor [$($entry.Monitor)] desktop $($entry.DesktopNumber); zones: $(@($zoneNames.Keys | Sort-Object) -join ', '))")
					}
				}
			}
		}

		$result.Variants += $keyText
		if ($blockErrors.Count -gt 0) {
			foreach ($message in $blockErrors) { $errors.Add($message) }
			continue
		}
		$validKeys.Add($keyText)
		$keyTokens[$keyText] = $tokens
	}
	$result.Errors = $errors.ToArray()

	# Which blocks apply, in selection order (a block covering two selected projects applies at
	# the first one, then again at the second - later wins either way).
	$selected = @($Project | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { ([string]$_).Trim() })
	$toApply = [System.Collections.Generic.List[string]]::new()
	foreach ($projectName in $selected) {
		foreach ($keyText in $validKeys) {
			if (@($keyTokens[$keyText] | Where-Object { $_ -ieq $projectName }).Count -gt 0) { $toApply.Add($keyText) }
		}
	}
	if ($toApply.Count -eq 0) { return $result }

	$merged = & $copyDeep $Config
	$merged.Remove('ProjectOverrides')
	if (-not ($merged['Monitors'] -is [hashtable])) { $merged['Monitors'] = @{} }
	$layout = [System.Collections.Generic.List[object]]::new()
	foreach ($entry in @($merged['Layout'])) { if ($null -ne $entry) { $layout.Add($entry) } }

	foreach ($keyText in $toApply) {
		$block = $overrides[($overrides.Keys | Where-Object { [string]$_ -eq $keyText } | Select-Object -First 1)]

		$blockMonitors = $block['Monitors']
		if ($blockMonitors -is [System.Collections.IDictionary]) {
			foreach ($monitorName in $blockMonitors.Keys) {
				$monitorOverride = $blockMonitors[$monitorName]
				if (-not ($merged['Monitors'][$monitorName] -is [hashtable])) { $merged['Monitors'][$monitorName] = @{} }
				$monitorTarget = $merged['Monitors'][$monitorName]
				if (-not ($monitorOverride -is [System.Collections.IDictionary])) { continue }
				foreach ($monitorKey in $monitorOverride.Keys) {
					$monitorValue = $monitorOverride[$monitorKey]
					if ($monitorValue -is [System.Collections.IDictionary] -and $monitorTarget[$monitorKey] -is [hashtable]) {
						foreach ($innerKey in $monitorValue.Keys) {
							# VirtualDesktopLayouts keys are desktop numbers - match them as numbers so
							# an override's 2 replaces the base's 2 whatever type the parser gave it.
							$existing = @($monitorTarget[$monitorKey].Keys | Where-Object { "$_" -eq "$innerKey" })
							foreach ($existingKey in $existing) { $monitorTarget[$monitorKey].Remove($existingKey) }
							$monitorTarget[$monitorKey][$innerKey] = & $copyDeep $monitorValue[$innerKey]
						}
					}
					else {
						$monitorTarget[$monitorKey] = & $copyDeep $monitorValue
					}
				}
			}
		}

		$blockEntries = @($block['Layout'] | Where-Object { $null -ne $_ })
		if ($blockEntries.Count -gt 0) {
			$pairs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
			foreach ($entry in $blockEntries) { [void]$pairs.Add("$([int]$entry.DesktopNumber)|$($entry.Monitor)") }

			# Replace in place, pair by pair: a pair's override entries take the position of the first
			# base entry they replace (file order is the stacking order); a pair the base does not use
			# goes to the end.
			$entriesByPair = [ordered]@{}
			foreach ($overrideEntry in $blockEntries) {
				$pairKey = "$([int]$overrideEntry.DesktopNumber)|$($overrideEntry.Monitor)"
				if (-not $entriesByPair.Contains($pairKey)) { $entriesByPair[$pairKey] = [System.Collections.Generic.List[object]]::new() }
				$entriesByPair[$pairKey].Add($overrideEntry)
			}
			$rebuilt = [System.Collections.Generic.List[object]]::new()
			$placedPairs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
			foreach ($entry in $layout) {
				$pairKey = "$(if ($null -ne $entry.DesktopNumber) { [int]$entry.DesktopNumber } else { 1 })|$($entry.Monitor)"
				if ($pairs.Contains($pairKey)) {
					if ($placedPairs.Add($pairKey)) {
						$matchingKey = @($entriesByPair.Keys | Where-Object { $_ -ieq $pairKey })[0]
						foreach ($overrideEntry in $entriesByPair[$matchingKey]) { $rebuilt.Add((& $copyDeep $overrideEntry)) }
					}
					continue
				}
				$rebuilt.Add($entry)
			}
			foreach ($pairKey in $entriesByPair.Keys) {
				if ($placedPairs.Contains($pairKey)) { continue }
				foreach ($overrideEntry in $entriesByPair[$pairKey]) { $rebuilt.Add((& $copyDeep $overrideEntry)) }
			}
			$layout = $rebuilt
		}

		$result.Applied += $keyText
	}

	$merged['Layout'] = $layout.ToArray()
	$result.Config = $merged
	return $result
}
