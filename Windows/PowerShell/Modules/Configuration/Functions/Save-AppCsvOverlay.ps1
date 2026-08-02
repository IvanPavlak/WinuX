function Save-AppCsvOverlay {
	<#
	.SYNOPSIS
		Writes the machine-local app list overlay, validating before it replaces anything.

	.DESCRIPTION
		The only function that writes an app overlay. It replaces `<name>.local.csv` wholesale from the
		rows it is given, having first proved the result parses and that every row is something the
		installers can actually act on.

		Only the overlay is written. The committed CSV is read to validate against and never modified,
		which is what keeps a fork's app choices out of a tracked file and stops an upstream pull from
		conflicting on one. `Import-AppCsv` then layers what is written here over the shipped list,
		exactly as the shell layers `Configuration.local.psd1` over `Configuration.psd1`.

		Validation, in order, all against a candidate in memory:

		1. Every row must carry a non-empty `App`.
		2. Every `Machine` cell must be composed of `All` or known machine types, joined with `/`. A blank
		   or unknown token silently matches nothing, so a row with one would look installed and never be,
		   which is the most confusing possible outcome.
		3. The candidate must round-trip through `Import-Csv` and come back with the same row count.

		Only then is the existing overlay copied to `<name>.local.csv.bak` and the candidate moved over
		it, staged in the destination folder so the replace is a same-volume rename a reader can never
		observe half-written. Restoring the `.bak` is a complete undo.

		A removal is expressed as a row whose `App` is `-<id>`, which is how the overlay opts out of an
		app the committed list ships. `Import-AppCsv` applies that; nothing here needs to know the base
		file's contents beyond validating machine tokens.

		Passing no rows writes an empty overlay (header only), which is the correct way to say "this
		machine adds nothing", and is different from deleting the overlay.

	.PARAMETER DataFileKey
		Which list to write: `WinGetApps`, `ScoopApps` or `ChocolateyApps`.

	.PARAMETER Row
		The overlay rows. Each must have an `App`; the remaining columns are taken from the committed
		file's header so the shape always matches what the installer reads.

	.PARAMETER RepoRoot
		Repository root the data-file path is resolved against. Defaults to the running repository.

	.PARAMETER NoBackup
		Skip the `.bak` copy. Not recommended; it removes the one-click undo.

	.EXAMPLE
		Save-AppCsvOverlay -DataFileKey WinGetApps -Row @(
			@{ App = 'Obsidian.Obsidian'; Version = 'Latest'; Scope = 'd'; Interactive = 'n'; Source = 'w'; Machine = 'All' }
		)
		Adds one app for every machine, leaving the committed list untouched.

	.EXAMPLE
		Save-AppCsvOverlay -DataFileKey WinGetApps -Row @(@{ App = '-Microsoft.PowerToys'; Machine = 'All' })
		Opts this machine out of a shipped app.

	.EXAMPLE
		Save-AppCsvOverlay -DataFileKey ScoopApps -Row @() -WhatIf
		Validates and reports what would be written without writing it.

	.NOTES
		Errors are raised as exceptions so a caller can surface them; progress goes to `Write-Verbose`.
		This keeps the writer usable from an interactive shell and from the compiled installer alike.
	#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	[OutputType([psobject])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateSet('WinGetApps', 'ScoopApps', 'ChocolateyApps')]
		[string]$DataFileKey,

		[Parameter(Mandatory = $false, Position = 1)]
		[AllowEmptyCollection()]
		[hashtable[]]$Row = @(),

		[Parameter(Mandatory = $false)]
		[string]$RepoRoot,

		[Parameter(Mandatory = $false)]
		[switch]$NoBackup
	)

	# A supplied-but-blank -RepoRoot is an accident, never an intention, and the fallback below is this
	# machine's own clone - so treating blank as "use the fallback" would quietly write an overlay beside
	# the tracked app lists when the caller meant to work in a sandbox. Omitting the parameter still uses
	# the fallback, which is what an interactive caller wants.
	if ($PSBoundParameters.ContainsKey('RepoRoot') -and [string]::IsNullOrWhiteSpace($RepoRoot)) {
		throw "-RepoRoot was given but is empty. Pass a real path, or omit the parameter to use this machine's own clone."
	}

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

	$overlayPath = [System.IO.Path]::ChangeExtension($basePath, $null) + 'local.csv'

	# The committed file's header defines the column order, so the overlay can never drift into a shape
	# the installer does not read.
	$headerLine = @(Get-Content -Path $basePath -TotalCount 1)[0]
	if ([string]::IsNullOrWhiteSpace($headerLine)) {
		throw "The app list [$basePath] has no header row."
	}
	$columns = @($headerLine -split ',' | ForEach-Object { $_.Trim() })

	$validTypes = @()
	if ($global:Configuration.ValidMachineTypes) {
		$validTypes = @($global:Configuration.ValidMachineTypes)
	}

	# --- validate every row before anything is written -------------------------------------------
	$rowIndex = 0
	foreach ($entry in $Row) {
		$appId = "$($entry.App)".Trim()
		if ([string]::IsNullOrWhiteSpace($appId)) {
			throw "Row $rowIndex has no App id, so there would be nothing to install."
		}

		$machineCell = "$($entry.Machine)".Trim()
		if ([string]::IsNullOrWhiteSpace($machineCell)) {
			throw "Row $rowIndex ($appId) is not assigned to any PC, so it would never install. Use All, or name a machine type."
		}

		foreach ($token in ($machineCell -split '/')) {
			$trimmed = $token.Trim()
			if ($trimmed -eq 'All') { continue }
			if ($validTypes -notcontains $trimmed) {
				throw "Row $rowIndex ($appId) targets '$trimmed', which is not a known machine type, so it would never install."
			}
		}

		$rowIndex++
	}

	# --- build the candidate ----------------------------------------------------------------------
	# The COLUMN row comes first and the commentary after it, matching the committed files. Import-Csv
	# takes line 1 as the header unconditionally, so a leading comment would be read as the header and
	# every real row would parse with a bogus column name and an empty App.
	$lines = [System.Collections.Generic.List[string]]::new()
	$lines.Add(($columns -join ','))
	$lines.Add('')
	$lines.Add("# $DataFileKey.local.csv - this machine's own app choices, layered over the committed list.")
	$lines.Add('# Written by Save-AppCsvOverlay. The committed CSV is never edited.')
	$lines.Add('# A row replaces a matching base row; a new App is added; an App written as -<id> removes one.')
	$lines.Add('')

	foreach ($entry in $Row) {
		$cells = foreach ($column in $columns) {
			$value = "$($entry[$column])"
			# Quote only when a cell would otherwise break the row apart.
			if ($value -match '[",]') { '"' + ($value -replace '"', '""') + '"' } else { $value }
		}
		$lines.Add(($cells -join ','))
	}

	$content = ($lines -join "`r`n") + "`r`n"

	# --- prove it parses back to the same rows ----------------------------------------------------
	$stagedPath = Join-Path -Path (Split-Path -Path $overlayPath -Parent) -ChildPath ((Split-Path -Path $overlayPath -Leaf) + '.' + [System.IO.Path]::GetRandomFileName() + '.tmp')
	try {
		[System.IO.File]::WriteAllText($stagedPath, $content, (New-Object System.Text.UTF8Encoding($false)))

		$parsed = @(Import-Csv -Path $stagedPath | Where-Object {
				-not [string]::IsNullOrWhiteSpace($_.App) -and -not $_.App.TrimStart().StartsWith('#')
			})

		if ($parsed.Count -ne $Row.Count) {
			throw "The overlay parsed back as $($parsed.Count) row(s) instead of $($Row.Count) - a value probably needs quoting."
		}
	}
	catch {
		Remove-Item -Path $stagedPath -Force -WhatIf:$false -Confirm:$false -ErrorAction SilentlyContinue
		throw "The app overlay would not be valid, so nothing was written => $($_.Exception.Message)"
	}

	$backupPath = "$overlayPath.bak"
	$overlayExists = Test-Path -Path $overlayPath

	if (-not $PSCmdlet.ShouldProcess($overlayPath, "Write $($Row.Count) app row(s)")) {
		Remove-Item -Path $stagedPath -Force -WhatIf:$false -Confirm:$false -ErrorAction SilentlyContinue
		return [pscustomobject]@{
			OverlayPath = $overlayPath
			BackupPath  = $null
			RowCount    = $Row.Count
			Written     = $false
		}
	}

	if ($overlayExists -and -not $NoBackup) {
		Copy-Item -Path $overlayPath -Destination $backupPath -Force
	}
	else {
		$backupPath = $null
	}

	try {
		Move-Item -Path $stagedPath -Destination $overlayPath -Force
	}
	catch {
		Remove-Item -Path $stagedPath -Force -WhatIf:$false -Confirm:$false -ErrorAction SilentlyContinue
		throw "Could not write the app overlay => $($_.Exception.Message)"
	}

	Write-Verbose "Wrote $($Row.Count) app row(s) to [$overlayPath]"

	return [pscustomobject]@{
		OverlayPath = $overlayPath
		BackupPath  = $backupPath
		RowCount    = $Row.Count
		Written     = $true
	}
}
