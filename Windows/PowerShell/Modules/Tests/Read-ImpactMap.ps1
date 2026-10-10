function Read-ImpactMap {
	<#
	.SYNOPSIS
		Reads the runtime impact map (Results\impact-map.json) and inverts it for Get-TestImpact.

	.DESCRIPTION
		Run-Tests -BuildImpactMap records, per test file, which functions it actually invoked. The
		static reference map misses dependencies created at runtime (commands invoked by a name read
		from configuration, Invoke-Expression, ...); this map is the backstop -Changed unions with it.

		A map is only trusted while it describes roughly the code being tested: one built for another
		Pester version, or more than MaxCommitsBehind commits ago, is ignored - and Note says so, so
		the selection output can tell you to rebuild it. A missing map is silently absent. Never
		throws.

	.PARAMETER Path
		The map file.

	.PARAMETER RepositoryRoot
		The repository, to count the commits since the map was built.

	.PARAMETER PesterVersion
		The pinned Pester version (RequiredPesterVersion.txt).

	.PARAMETER MaxCommitsBehind
		How many commits a map may lag HEAD. Defaults to 50.

	.OUTPUTS
		[pscustomobject] Map (hashtable: function file path relative to the PowerShell root ->
		string[] test file paths, same base; $null when unusable), Note (string or $null).

	.EXAMPLE
		Read-ImpactMap -Path $mapFile -RepositoryRoot $root -PesterVersion '6.1.0'
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Path,

		[Parameter()]
		[string]$RepositoryRoot,

		[Parameter()]
		[string]$PesterVersion,

		[Parameter()]
		[int]$MaxCommitsBehind = 50
	)

	$none = { param([string]$Note) [pscustomobject]@{ Map = $null; Note = $Note } }

	try {
		if (-not (Test-Path -LiteralPath $Path)) { return & $none $null }
		$document = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

		if ($PesterVersion -and [string]$document.pester -ne $PesterVersion) {
			return & $none "impact map ignored - built with Pester $($document.pester), the pin is $PesterVersion; rebuild it with Run-Tests -BuildImpactMap"
		}
		if ($RepositoryRoot -and $document.commit) {
			$behind = @(git -C $RepositoryRoot rev-list --count "$($document.commit)..HEAD" 2>$null)[0]
			if ($LASTEXITCODE -ne 0) {
				return & $none "impact map ignored - its commit $($document.commit) is not in this history; rebuild it with Run-Tests -BuildImpactMap"
			}
			if ([int]$behind -gt $MaxCommitsBehind) {
				return & $none "impact map ignored - built $behind commits ago (limit $MaxCommitsBehind); rebuild it with Run-Tests -BuildImpactMap"
			}
		}

		$map = @{}
		foreach ($test in $document.tests.PSObject.Properties) {
			foreach ($function in @($test.Value)) {
				if (-not $function) { continue }
				if (-not $map.ContainsKey($function)) { $map[$function] = [System.Collections.Generic.List[string]]::new() }
				$map[$function].Add($test.Name)
			}
		}
		$inverted = @{}
		foreach ($key in $map.Keys) { $inverted[$key] = [string[]]@($map[$key]) }
		return [pscustomobject]@{ Map = $inverted; Note = $null }
	}
	catch {
		return & $none "impact map ignored - it could not be read ($($_.Exception.Message))"
	}
}
