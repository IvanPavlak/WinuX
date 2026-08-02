function Import-AppCsv {
	<#
	.SYNOPSIS
		Reads an app list CSV, layering a machine-local overlay over the committed one.

	.DESCRIPTION
		The single read path for the three app lists. It parses the committed CSV named by
		`BootstrapConfig.DataFiles`, then layers a sibling `<name>.local.csv` over it when one exists,
		and returns the combined active rows.

		This mirrors, for app lists, exactly what `Configuration.local.psd1` does for settings. The
		committed CSV stays the shipped baseline that upstream can keep improving, and everything a
		person chose for this machine lives in the overlay beside it. A fork therefore never has to edit
		a tracked file to change its own app list, and pulling upstream never conflicts on one.

		Layering rules:

		- An overlay row whose `App` matches a base row **replaces** it. That is what lets the overlay
		  pin a version, change the install scope, or re-target a machine without touching the base.
		  Matching is case-insensitive, because package ids are.
		- An overlay row with a new `App` is **added**.
		- An overlay row whose `App` is `-` (or blank after the marker) **removes** the base row. Without
		  this there would be no way to opt out of a shipped app, since a layer that can only add or
		  replace cannot subtract.
		- Comment rows (`App` starting with `#`) and blank `App` cells are dropped from both files, which
		  is what the callers used to do individually.

		Row order is base-first, then overlay-only additions, so the shipped install order is preserved
		and a user's own apps follow.

		A missing overlay is the normal case and is not an error. A missing base file is, since it is a
		tracked file the repository is supposed to ship.

	.PARAMETER DataFileKey
		Which list to read: `WinGetApps`, `ScoopApps` or `ChocolateyApps`. Resolved through
		`BootstrapConfig.DataFiles`, so the location stays configuration-driven.

	.PARAMETER RepoRoot
		Repository root the relative data-file path is resolved against. Defaults to the running
		repository.

	.EXAMPLE
		Import-AppCsv -DataFileKey WinGetApps
		Returns the active WinGet rows, with any machine-local overlay applied.

	.EXAMPLE
		Import-AppCsv -DataFileKey ScoopApps | Where-Object { $_.Global -eq 'true' }
		Filters the combined list the same way a caller would filter a plain Import-Csv result.

	.NOTES
		This only reads. `Save-AppCsvOverlay` writes the overlay, and the committed CSV is never
		modified by either.
	#>
	[CmdletBinding()]
	[OutputType([psobject[]])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateSet('WinGetApps', 'ScoopApps', 'ChocolateyApps')]
		[string]$DataFileKey,

		[Parameter(Mandatory = $false)]
		[string]$RepoRoot
	)

	if (-not $RepoRoot) {
		$RepoRoot = $global:MachineSpecificPaths.Projects.Self.Root
	}

	if (-not $RepoRoot) {
		throw "Cannot locate the repository - pass -RepoRoot."
	}

	$relativePath = $global:Configuration.BootstrapConfig.DataFiles.$DataFileKey
	if ([string]::IsNullOrWhiteSpace($relativePath)) {
		throw "BootstrapConfig.DataFiles.$DataFileKey is not configured."
	}

	$basePath = Join-Path -Path $RepoRoot -ChildPath $relativePath
	if (-not (Test-Path -Path $basePath)) {
		throw "App list not found => [$basePath]"
	}

	# The overlay sits beside the base file: WinGetApps.csv -> WinGetApps.local.csv
	$overlayPath = [System.IO.Path]::ChangeExtension($basePath, $null) + 'local.csv'

	$baseRows = @(Import-Csv -Path $basePath | Where-Object {
			-not [string]::IsNullOrWhiteSpace($_.App) -and -not $_.App.TrimStart().StartsWith('#')
		})

	# The casts on the two no-overlay returns are what keep every exit path on the declared OutputType:
	# `@(...)` is an Object[], while the layered path below returns psobject[] from the List. Without
	# them the function advertises one element type and hands back another depending on whether an
	# overlay happened to exist.
	if (-not (Test-Path -Path $overlayPath)) {
		return [psobject[]]$baseRows
	}

	$overlayRows = @(Import-Csv -Path $overlayPath | Where-Object {
			-not [string]::IsNullOrWhiteSpace($_.App) -and -not $_.App.TrimStart().StartsWith('#')
		})

	if ($overlayRows.Count -eq 0) {
		return [psobject[]]$baseRows
	}

	# Index the overlay by app id so a base row can be replaced or removed in one pass.
	$replacements = @{}
	$removals = @{}

	foreach ($row in $overlayRows) {
		$appId = "$($row.App)".Trim()

		# A leading '-' marks a removal, which is the only way to opt out of a shipped app.
		if ($appId.StartsWith('-')) {
			$target = $appId.Substring(1).Trim()
			if (-not [string]::IsNullOrWhiteSpace($target)) {
				$removals[$target.ToLowerInvariant()] = $true
			}
			continue
		}

		$replacements[$appId.ToLowerInvariant()] = $row
	}

	$result = [System.Collections.Generic.List[psobject]]::new()
	$consumed = @{}

	foreach ($row in $baseRows) {
		$key = "$($row.App)".Trim().ToLowerInvariant()

		if ($removals.ContainsKey($key)) { continue }

		if ($replacements.ContainsKey($key)) {
			$result.Add($replacements[$key])
			$consumed[$key] = $true
			continue
		}

		$result.Add($row)
	}

	# Overlay rows that matched nothing in the base are this machine's own additions, kept in the
	# order the overlay lists them and appended after the shipped set.
	foreach ($row in $overlayRows) {
		$appId = "$($row.App)".Trim()
		if ($appId.StartsWith('-')) { continue }

		$key = $appId.ToLowerInvariant()
		if ($consumed.ContainsKey($key)) { continue }
		if ($removals.ContainsKey($key)) { continue }

		$result.Add($row)
		$consumed[$key] = $true
	}

	Write-LogDebug "[$DataFileKey] $($baseRows.Count) base row(s), $($overlayRows.Count) overlay row(s) => $($result.Count) active"

	return $result.ToArray()
}
