function Get-VirtualDesktopGuid {
	<#
	.SYNOPSIS
		Resolves the GUID of a virtual desktop by its 0-based index.

	.DESCRIPTION
		Reads the ordered list of virtual desktop GUIDs from the Windows registry value
		`VirtualDesktopIDs` and returns the GUID for the requested 0-based index, formatted
		as an upper-case braced string (e.g., "{CF6C2856-0D59-466D-AA7F-E6DF85C6034C}").
		This is the same GUID FancyZones records per desktop in applied-layouts.json, so it
		can be used to correlate a live desktop with its applied FancyZones layout. Returns
		$null when the registry value is unavailable or the index is out of range.

	.PARAMETER DesktopIndex
		The 0-based virtual desktop index to resolve.

	.OUTPUTS
		String GUID in "{UPPER-CASE}" form, or $null when it cannot be resolved.

	.EXAMPLE
		Get-VirtualDesktopGuid -DesktopIndex 0
		# Returns the GUID of the first virtual desktop.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory = $true)]
		[int]$DesktopIndex
	)

	$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops"

	try {
		$vdIds = (Get-ItemProperty -Path $regPath -Name "VirtualDesktopIDs" -ErrorAction Stop).VirtualDesktopIDs
	}
	catch {
		return $null
	}

	$guidSize = 16
	if (-not $vdIds -or $vdIds.Length -lt $guidSize) {
		return $null
	}

	$vdCount = [math]::Floor($vdIds.Length / $guidSize)
	if ($DesktopIndex -lt 0 -or $DesktopIndex -ge $vdCount) {
		return $null
	}

	$bytes = $vdIds[($DesktopIndex * $guidSize)..((($DesktopIndex + 1) * $guidSize) - 1)]
	$guid = [System.Guid]::new([byte[]]$bytes)
	return "{$($guid.ToString().ToUpper())}"
}
