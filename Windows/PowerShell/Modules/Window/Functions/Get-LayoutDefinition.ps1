function Get-LayoutDefinition {
	<#
	.SYNOPSIS
		Loads layout definitions from custom-layouts.json file.

	.DESCRIPTION
		Retrieves a specific FancyZones layout definition from the custom-layouts.json
		configuration file. Used internally by the layout visualization system.

	.PARAMETER LayoutsJsonPath
		Path to the custom-layouts.json file.

	.PARAMETER LayoutName
		Name of the layout to retrieve (e.g., "Zero", "One", "Eight").

	.EXAMPLE
		$layout = Get-LayoutDefinition -LayoutsJsonPath "C:\...\custom-layouts.json" -LayoutName "Eight"

	.OUTPUTS
		The layout definition object, or $null if not found.
	#>
	[CmdletBinding()]
	param (
		[string]$LayoutsJsonPath,
		[string]$LayoutName
	)

	if (-not (Test-Path $LayoutsJsonPath)) {
		Write-Error "Layouts file not found: $LayoutsJsonPath"
		return $null
	}

	try {
		# Use cached JSON data to avoid repeated file reads
		$layoutsData = Get-CachedFancyZonesLayouts -LayoutsJsonPath $LayoutsJsonPath
		if ($null -eq $layoutsData) {
			Write-Error "Failed to load layouts JSON"
			return $null
		}
		$layout = $layoutsData.'custom-layouts' | Where-Object { $_.name -eq $LayoutName }
		return $layout
	}
	catch {
		Write-Error "Failed to parse layouts JSON: $_"
		return $null
	}
}
