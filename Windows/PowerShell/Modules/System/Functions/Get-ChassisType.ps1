function Get-ChassisType {
	<#
	.SYNOPSIS
		Returns the machine's SMBIOS chassis type codes, from a per-machine cache after the first
		call.

	.DESCRIPTION
		The chassis type (Win32_SystemEnclosure.ChassisTypes - 3 for a desktop, 9 or 10 for a
		laptop, and so on) is what Test-PowerPlan uses to decide which power plan a machine should
		run. Reading it through CIM loads the CimCmdlets module and takes a WMI round trip, which
		on every shell start was the largest part of that check - for a value that never changes
		on a given machine.

		So it is read from the hardware once and written to a small cache file, one code per line.
		Every later call reads the file. -Refresh queries the hardware again and rewrites the file.
		A cache that is missing, empty, unreadable or holds anything but integers is ignored and
		re-created; a cache directory that cannot be created just means the hardware is queried
		every time, so the function works without the cache.

	.PARAMETER Refresh
		Ignore the cache, query the hardware and rewrite the cache.

	.PARAMETER CachePath
		The cache file. Defaults to %LOCALAPPDATA%\WinuX\ChassisTypes.txt.

	.OUTPUTS
		[int[]] - the chassis type codes; empty when neither the cache nor the hardware answered.

	.EXAMPLE
		Get-ChassisType
		3 on a desktop, 10 on a notebook - from the cache after the first call.

	.EXAMPLE
		Get-ChassisType -Refresh
		Re-reads the hardware, for example after moving the cache between machines.
	#>
	[CmdletBinding()]
	[OutputType([int[]])]
	param(
		[Parameter()]
		[switch]$Refresh,

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string]$CachePath = (Join-Path $env:LOCALAPPDATA "WinuX\ChassisTypes.txt")
	)

	if (-not $Refresh -and (Test-Path -LiteralPath $CachePath -PathType Leaf)) {
		$cached = [System.Collections.Generic.List[int]]::new()
		$valid = $true
		foreach ($line in [System.IO.File]::ReadAllLines($CachePath)) {
			if ([string]::IsNullOrWhiteSpace($line)) { continue }
			$code = 0
			if ([int]::TryParse($line.Trim(), [ref]$code)) { $cached.Add($code) } else { $valid = $false; break }
		}
		if ($valid -and $cached.Count -gt 0) {
			Write-LogDebug "[Get-ChassisType] cached chassis type(s) [$($cached -join ', ')] from [$CachePath]"
			return [int[]]$cached.ToArray()
		}
		Write-LogDebug "[Get-ChassisType] cache [$CachePath] is empty or unreadable - querying the hardware"
	}

	$types = @((Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes | ForEach-Object { [int]$_ })

	if ($types.Count -gt 0) {
		try {
			$directory = Split-Path -Parent $CachePath
			if ($directory -and -not (Test-Path -LiteralPath $directory)) {
				New-Item -ItemType Directory -Path $directory -Force | Out-Null
			}
			[System.IO.File]::WriteAllLines($CachePath, [string[]]($types | ForEach-Object { "$_" }))
			Write-LogDebug "[Get-ChassisType] chassis type(s) [$($types -join ', ')] cached to [$CachePath]"
		}
		catch {
			Write-LogDebug "[Get-ChassisType] could not write the cache [$CachePath] => $($_.Exception.Message)"
		}
	}

	return [int[]]$types
}
