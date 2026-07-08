function Generate-LayoutVisualization {
	<#
	.SYNOPSIS
		Generates ASCII art visualization of a FancyZones layout.

	.DESCRIPTION
		Creates an ASCII art representation of a FancyZones layout showing which
		processes and windows are assigned to each zone. The visualization is
		dynamically generated based on the layout definition in custom-layouts.json,
		supporting any grid-based layout configuration.

	.PARAMETER LayoutType
		The FancyZones layout type (Zero, One, Two, etc.).

	.PARAMETER Windows
		Array of window configurations for this layout.

	.PARAMETER DesktopNumber
		The virtual desktop number (1-based, e.g., 1 for first desktop).

	.PARAMETER MonitorName
		The monitor name (Primary, Secondary, etc.).

	.PARAMETER LayoutsJsonPath
		Optional path to custom-layouts.json. Defaults to standard location.

	.EXAMPLE
		Generate-LayoutVisualization -LayoutType "One" -Windows $windows -DesktopNumber 1 -MonitorName "Primary"

	.OUTPUTS
		String containing the ASCII art visualization.
	#>
	param (
		[string]$LayoutType,
		[array]$Windows,
		[int]$DesktopNumber,
		[string]$MonitorName,
		[string]$LayoutsJsonPath
	)

	# Determine layouts JSON path dynamically if not provided
	if (-not $LayoutsJsonPath) {
		# Determine WinuX root
		$repoRoot = $null

		# Try to get from global variable
		if ($global:RepoRoot -and (Test-Path $global:RepoRoot)) {
			$repoRoot = $global:RepoRoot
		}

		# If not found, navigate from module path
		if (-not $repoRoot) {
			# Path: .../WinuX/Windows/PowerShell/Modules/Window/Functions -> .../WinuX
			$modulePath = $PSScriptRoot
			$currentPath = $modulePath
			for ($i = 0; $i -lt 5; $i++) {
				$currentPath = Split-Path $currentPath -Parent
			}

			# Verify this looks like WinuX root (has Windows\FancyZones)
			$testPath = Join-Path $currentPath "Windows\FancyZones"
			if (Test-Path $testPath) {
				$repoRoot = $currentPath
			}
		}

		# Build the layouts JSON path
		if ($repoRoot) {
			$LayoutsJsonPath = Join-Path $repoRoot "Windows\FancyZones\custom-layouts.json"
		}
		else {
			Write-Error "Could not determine WinuX root path. Please provide -LayoutsJsonPath parameter."
			return
		}
	}

	$zoneMapping = $global:Configuration.ZoneNameMappings

	# Build reverse mapping: zone index -> zone name for empty zone labels
	$zoneIndexToName = @{}
	if ($zoneMapping[$LayoutType]) {
		foreach ($name in $zoneMapping[$LayoutType].Keys) {
			$index = $zoneMapping[$LayoutType][$name]
			# If multiple names map to same index, prefer longer/more descriptive names
			if (-not $zoneIndexToName.ContainsKey($index) -or $name.Length -gt $zoneIndexToName[$index].Length) {
				$zoneIndexToName[$index] = $name
			}
		}
	}

	# Build zone content map
	$zoneContent = @{}
	foreach ($window in $Windows) {
		$zoneName = $window.Zone
		if ($zoneMapping[$LayoutType] -and $zoneMapping[$LayoutType].ContainsKey($zoneName)) {
			$zoneIndex = $zoneMapping[$LayoutType][$zoneName]

			# Build process name (with window title if available).
			# When ProcessName and WindowTitle are the same layout token (e.g. both "Browser"),
			# render the label only once to keep the visualization clean.
			$processName = if ($window.WindowTitle -and $null -ne $window.WindowTitle -and
				$window.WindowTitle -cne $window.ProcessName) {
				"$($window.ProcessName)`n$($window.WindowTitle)"
			}
			else {
				$window.ProcessName
			}

			# Only add non-empty process names to zone content
			if (-not [string]::IsNullOrWhiteSpace($processName)) {
				if (-not $zoneContent.ContainsKey($zoneIndex)) {
					$zoneContent[$zoneIndex] = @()
				}
				$zoneContent[$zoneIndex] += $processName
			}
		}
	}

	# Generate the visual based on layout definition
	$header = "VIRTUAL DESKTOP $DesktopNumber - Monitor: $MonitorName - Layout: $LayoutType"

	# Load layout definition
	$layoutDef = Get-LayoutDefinition -LayoutsJsonPath $LayoutsJsonPath -LayoutName $LayoutType

	if ($null -eq $layoutDef) {
		$visual = "`nLayout type [$LayoutType] not found in $LayoutsJsonPath"
	}
	elseif ($layoutDef.type -ne "grid") {
		$visual = "`nLayout type [$($layoutDef.type)] is not supported (only grid layouts are supported)"
	}
	else {
		# Generate dynamic visualization
		$visual = Generate-DynamicVisualization -LayoutInfo $layoutDef.info -ZoneContent $zoneContent -ZoneNames $zoneIndexToName
	}

	return "$header`n$visual"
}
