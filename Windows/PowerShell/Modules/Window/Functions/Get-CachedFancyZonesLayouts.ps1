function Get-CachedFancyZonesLayouts {
	<#
	.SYNOPSIS
		Gets cached FancyZones layout data.

	.DESCRIPTION
		Returns FancyZones layout configuration from cache if still valid,
		otherwise reads and parses the JSON file. This avoids repeated
		file I/O and JSON parsing operations.

	.PARAMETER LayoutsJsonPath
		Path to the FancyZones custom-layouts.json file.

	.OUTPUTS
		PSObject containing parsed FancyZones layout data, or $null if file not found.

	.EXAMPLE
		$layouts = Get-CachedFancyZonesLayouts -LayoutsJsonPath "C:\Users\...\custom-layouts.json"
	#>
	param(
		[Parameter(Mandatory = $true)]
		[string]$LayoutsJsonPath
	)

	$now = [datetime]::Now
	$age = ($now - $script:FancyZonesCache.Timestamp).TotalSeconds

	# Return cached data if same path and not expired
	if ($script:FancyZonesCache.Path -eq $LayoutsJsonPath -and
		$null -ne $script:FancyZonesCache.Data -and
		$age -lt $script:FancyZonesCache.MaxAgeSec) {
		return $script:FancyZonesCache.Data
	}

	# Cache miss or expired - reload
	if (-not (Test-Path $LayoutsJsonPath)) {
		return $null
	}

	try {
		$script:FancyZonesCache.Data = Get-Content $LayoutsJsonPath -Raw | ConvertFrom-Json
		$script:FancyZonesCache.Path = $LayoutsJsonPath
		$script:FancyZonesCache.Timestamp = $now
		return $script:FancyZonesCache.Data
	}
	catch {
		Write-Warning "Failed to parse FancyZones layouts: $_"
		return $null
	}
}
