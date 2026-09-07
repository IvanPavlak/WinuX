function Measure-WorkspaceOpen {
	<#
	.SYNOPSIS
		Opens one workspace many times under alternating configuration variants and compares them.

	.DESCRIPTION
		The controlled experiment behind the Open-Workspace speed work. A single benchmark row says
		how long one open took; it cannot say whether a configuration flag made it faster, because
		the spread between two opens of the SAME configuration (a cold browser start against a warm
		one, a layout retry) is larger than the effect of any flag. Deciding by hand also means
		remembering which flag was on for which row, tearing down the same way every time, and not
		stopping after the run that confirmed the hunch. This function does all of that itself.

		For every variant it puts the variant's values into the live configuration, and for every
		run it tears the machine down (Kill-All -Skip Docker by default), waits -SettleSeconds for
		the dust to settle, opens the workspace through the real Open-Workspace, and takes the
		benchmark row that open appended (Write-WorkspaceBenchmark). Runs are interleaved by default
		- round 1 of every variant, then round 2, and so on - so a slow hour hits every variant
		alike instead of one. -WarmUp opens (one by default) run first under the baseline and are
		recorded but never counted, because the first open after a reboot pays the disk cache for
		everybody. Every configuration key the experiment touched is restored when it ends, whether
		it finished or was interrupted.

		Which variants run:
		  - Without -Variant, the one-factor-at-a-time set over -Setting (all three layout flags by
		    default): the current configuration as "Baseline", plus one variant per setting with
		    ONLY that setting flipped. Four opens per round for the three flags.
		  - -FullFactorial instead runs every combination of the -Setting values (2^n variants).
		  - -Variant runs exactly the hashtables given. Every key is a configuration key and its
		    value is what the run gets; an optional Name key labels the variant. Any key works, not
		    only the three layout flags, so a delay or a retry count can be compared the same way.

		Every measured run is appended to WorkspaceOpenMeasurements.csv beside the benchmark file:
		the session id, variant name, round, the three layout flags as they were in effect, the
		variant's own overrides, and the whole benchmark row. Nothing is thrown away - a run whose
		open produced no benchmark row is recorded with Outcome NoRow, one that threw with Error.

		The result is one summary per variant, printed as a table and returned as objects: the
		number of measured runs, how many ended Applied on the first attempt, the retries, the
		median/min/max total, and the medians of the phases the flags control (Layout, FancyZones,
		Wait, Position+Snap, Verify), plus the median total over the clean runs only. Medians, not
		averages - one 40-second outlier must not decide the experiment. Read Retries and Applied
		before the seconds: a variant that wins the median by needing a retry every third run has
		not won.

		Refuses to run a workspace whose actions include Terminate-WindowsTerminalTabs -OnlyCurrent
		or -IncludeCurrent, because that action ends the calling process and would end the
		experiment with it. -DryRun prints the plan (variants, order, opens) and changes nothing.

	.PARAMETER Workspace
		The workspace to open. Must be configured in WorkspaceActions.

	.PARAMETER Runs
		Measured opens per variant. 5 by default.

	.PARAMETER Setting
		The layout flags to vary when -Variant is not given: FancyZonesApplyMethod (File or
		Hotkeys), WorkspaceLayoutPipelining and WorkspaceLayoutPrepareEarly (on or off). All three
		by default.

	.PARAMETER FullFactorial
		Run every combination of the -Setting values instead of flipping one at a time.

	.PARAMETER Variant
		Explicit variants: one hashtable each, configuration key to value, with an optional Name.

	.PARAMETER WarmUp
		Opens to run first under the baseline and exclude from every summary. 1 by default.

	.PARAMETER SettleSeconds
		Pause between the teardown and the next open. 5 by default.

	.PARAMETER Teardown
		Script block run before every open. { Kill-All -Skip Docker } by default.

	.PARAMETER Order
		Interleaved (round-robin over the variants, the default), Shuffled (a random permutation
		of the variants per round; -Seed makes it reproducible) or Sequential (all runs of one
		variant, then the next - the order humans use and the one the experiment exists to avoid).

	.PARAMETER Seed
		Seed for -Order Shuffled.

	.PARAMETER DryRun
		Print the plan and return it without opening, tearing down or touching the configuration.

	.PARAMETER ResultPath
		Write the per-run rows to a different file. Defaults to WorkspaceOpenMeasurements.csv next
		to the benchmark file.

	.PARAMETER BenchmarkPath
		Read the benchmark rows from a different file. Defaults to Get-WorkspaceBenchmarkPath.

	.PARAMETER Configuration
		The configuration hashtable to modify and restore. Defaults to $global:Configuration, the
		one Open-Workspace and Set-WorkspaceWindowLayout read.

	.PARAMETER PassThru
		Return the per-run rows in addition to the summary, as the Runs property of a single
		result object with Summary and Runs.

	.EXAMPLE
		Measure-WorkspaceOpen WinuX
		# 1 warm-up, then 5 rounds of Baseline + each layout flag flipped alone: 21 opens.

	.EXAMPLE
		Measure-WorkspaceOpen WinuX -Setting FancyZonesApplyMethod -Runs 8
		# Only File against Hotkeys, 8 measured opens each, interleaved.

	.EXAMPLE
		Measure-WorkspaceOpen WinuX -FullFactorial -Runs 3
		# All 8 combinations of the three flags, 3 opens each.

	.EXAMPLE
		Measure-WorkspaceOpen WinuX -Variant @{ Name = 'Current' }, @{ Name = 'AllOff'; FancyZonesApplyMethod = 'Hotkeys'; WorkspaceLayoutPipelining = $false; WorkspaceLayoutPrepareEarly = $false }

	.EXAMPLE
		Measure-WorkspaceOpen WinuX -DryRun
		# Shows what would run, in which order, and how many opens that is.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Workspace,

		[Parameter()]
		[ValidateRange(1, 200)]
		[int]$Runs = 5,

		[Parameter()]
		[ValidateSet('FancyZonesApplyMethod', 'WorkspaceLayoutPipelining', 'WorkspaceLayoutPrepareEarly')]
		[string[]]$Setting = @('FancyZonesApplyMethod', 'WorkspaceLayoutPipelining', 'WorkspaceLayoutPrepareEarly'),

		[Parameter()]
		[switch]$FullFactorial,

		[Parameter()]
		[hashtable[]]$Variant,

		[Parameter()]
		[ValidateRange(0, 20)]
		[int]$WarmUp = 1,

		[Parameter()]
		[ValidateRange(0, 600)]
		[int]$SettleSeconds = 5,

		[Parameter()]
		[scriptblock]$Teardown = { Kill-All -Skip Docker },

		[Parameter()]
		[ValidateSet('Interleaved', 'Shuffled', 'Sequential')]
		[string]$Order = 'Interleaved',

		[Parameter()]
		[int]$Seed,

		[Parameter()]
		[switch]$DryRun,

		[Parameter()]
		[string]$ResultPath,

		[Parameter()]
		[string]$BenchmarkPath,

		[Parameter()]
		[hashtable]$Configuration = $global:Configuration,

		[Parameter()]
		[switch]$PassThru
	)

	Write-LogTitle "Workspace Open Measurement"

	$invariant = [System.Globalization.CultureInfo]::InvariantCulture

	# The three layout flags, their two values, and the value the shipped configuration means when
	# the key is absent. "Hotkeys" is the only value Apply-FancyZones treats as not-File.
	$knownSettings = [ordered]@{
		FancyZonesApplyMethod       = @{ Options = @('File', 'Hotkeys'); Default = 'File' }
		WorkspaceLayoutPipelining   = @{ Options = @($true, $false); Default = $true }
		WorkspaceLayoutPrepareEarly = @{ Options = @($true, $false); Default = $true }
	}

	if ($null -eq $Configuration) {
		Write-LogError "No configuration is loaded - Measure-WorkspaceOpen needs `$global:Configuration (or -Configuration) to set the variants on." -NoLeadingNewline
		return
	}

	$workspaceActions = $null
	if ($Configuration.WorkspaceActions) { $workspaceActions = $Configuration.WorkspaceActions[$Workspace] }
	if (-not $workspaceActions) {
		Write-LogError "Workspace [$Workspace] is not configured in WorkspaceActions." -NoLeadingNewline
		return
	}

	# Terminate-WindowsTerminalTabs -OnlyCurrent / -IncludeCurrent ends THIS process; one such
	# action and the experiment would end with its first open.
	foreach ($action in @($workspaceActions)) {
		if ($action.Action -ne 'Terminate-WindowsTerminalTabs') { continue }
		$parameters = $action.Parameters
		if ($parameters -and (($parameters.ContainsKey('OnlyCurrent') -and $parameters['OnlyCurrent']) -or ($parameters.ContainsKey('IncludeCurrent') -and $parameters['IncludeCurrent']))) {
			Write-LogError "Workspace [$Workspace] ends with Terminate-WindowsTerminalTabs -OnlyCurrent/-IncludeCurrent, which exits the calling shell - it cannot be measured in a loop." -NoLeadingNewline
			return
		}
	}

	# Current effective value of a layout flag: the configured one, normalized, else the shipped
	# default. Used to build the variants and to stamp every row with what was in effect.
	$effectiveSetting = {
		param([string]$Key, [hashtable]$Config)
		$definition = $knownSettings[$Key]
		$raw = $Config[$Key]
		if ($null -eq $raw) { return $definition.Default }
		if ($Key -eq 'FancyZonesApplyMethod') {
			return $(if (([string]$raw).Trim() -ieq 'Hotkeys') { 'Hotkeys' } else { 'File' })
		}
		return [bool]$raw
	}

	$formatValue = {
		param($Value)
		if ($Value -is [bool]) { return $(if ($Value) { 'On' } else { 'Off' }) }
		return [string]$Value
	}

	$shortLabel = @{
		FancyZonesApplyMethod       = 'ApplyMethod'
		WorkspaceLayoutPipelining   = 'Pipelining'
		WorkspaceLayoutPrepareEarly = 'PrepareEarly'
	}

	$describeOverrides = {
		param([System.Collections.IDictionary]$Overrides)
		$parts = foreach ($key in $Overrides.Keys) {
			$label = if ($shortLabel.ContainsKey($key)) { $shortLabel[$key] } else { [string]$key }
			"$label=$(& $formatValue $Overrides[$key])"
		}
		return ($parts -join ' ')
	}

	# ---- Variants -------------------------------------------------------------------------------
	# Each variant: Name, Overrides (ordered configuration key -> value). Baseline has none.
	$variants = [System.Collections.Generic.List[pscustomobject]]::new()
	$settings = @($Setting | Select-Object -Unique)

	if ($Variant) {
		$index = 0
		foreach ($given in $Variant) {
			$index++
			# Known flags first, in their fixed order, then any other key alphabetically, so the
			# name reads the same however the hashtable was typed.
			$overrides = [ordered]@{}
			foreach ($key in $knownSettings.Keys) {
				if ($given.ContainsKey($key)) { $overrides[$key] = $given[$key] }
			}
			foreach ($key in @($given.Keys | Sort-Object)) {
				if ($key -eq 'Name' -or $overrides.Contains([string]$key)) { continue }
				$overrides[[string]$key] = $given[$key]
			}
			$name = if (-not [string]::IsNullOrWhiteSpace([string]$given['Name'])) { ([string]$given['Name']).Trim() }
			elseif ($overrides.Count -gt 0) { & $describeOverrides $overrides }
			else { "Variant $index" }
			$variants.Add([PSCustomObject]@{ Name = $name; Overrides = $overrides })
		}
	}
	elseif ($FullFactorial) {
		$combinations = @([ordered]@{})
		foreach ($key in $settings) {
			$expanded = foreach ($combination in $combinations) {
				foreach ($value in $knownSettings[$key].Options) {
					$next = [ordered]@{}
					foreach ($existing in $combination.Keys) { $next[$existing] = $combination[$existing] }
					$next[$key] = $value
					$next
				}
			}
			$combinations = @($expanded)
		}
		foreach ($combination in $combinations) {
			$variants.Add([PSCustomObject]@{ Name = (& $describeOverrides $combination); Overrides = $combination })
		}
	}
	else {
		$variants.Add([PSCustomObject]@{ Name = 'Baseline'; Overrides = [ordered]@{} })
		foreach ($key in $settings) {
			$current = & $effectiveSetting $key $Configuration
			$flipped = @($knownSettings[$key].Options | Where-Object { $_ -ne $current }) | Select-Object -First 1
			$overrides = [ordered]@{ $key = $flipped }
			$variants.Add([PSCustomObject]@{ Name = (& $describeOverrides $overrides); Overrides = $overrides })
		}
	}

	# Duplicate names would merge two variants in the summary; make them unique.
	$seenNames = @{}
	foreach ($entry in $variants) {
		if ($seenNames.ContainsKey($entry.Name)) {
			$seenNames[$entry.Name]++
			$entry.Name = "$($entry.Name) #$($seenNames[$entry.Name])"
		}
		else { $seenNames[$entry.Name] = 1 }
	}

	# ---- Schedule -------------------------------------------------------------------------------
	# Warm-ups first (round 0, baseline = the first variant), then the measured rounds.
	$schedule = [System.Collections.Generic.List[pscustomobject]]::new()
	for ($i = 1; $i -le $WarmUp; $i++) {
		$schedule.Add([PSCustomObject]@{ Variant = $variants[0]; Round = 0; Measured = $false })
	}

	$random = if ($PSBoundParameters.ContainsKey('Seed')) { [System.Random]::new($Seed) } else { [System.Random]::new() }
	switch ($Order) {
		'Sequential' {
			foreach ($entry in $variants) {
				for ($round = 1; $round -le $Runs; $round++) {
					$schedule.Add([PSCustomObject]@{ Variant = $entry; Round = $round; Measured = $true })
				}
			}
		}
		default {
			for ($round = 1; $round -le $Runs; $round++) {
				$roundVariants = @($variants)
				if ($Order -eq 'Shuffled') {
					$roundVariants = @($roundVariants | Sort-Object { $random.Next() })
				}
				foreach ($entry in $roundVariants) {
					$schedule.Add([PSCustomObject]@{ Variant = $entry; Round = $round; Measured = $true })
				}
			}
		}
	}

	Write-LogStep " Workspace [$Workspace] => $($variants.Count) variant(s), $Runs run(s) each, $WarmUp warm-up(s): $($schedule.Count) opens, $Order order"
	foreach ($entry in $variants) {
		$detail = if ($entry.Overrides.Count -gt 0) { & $describeOverrides $entry.Overrides } else { 'current configuration' }
		Write-LogStep "   [$($entry.Name)] => $detail"
	}

	if ($DryRun) {
		$position = 0
		return @($schedule | ForEach-Object {
				$position++
				[PSCustomObject]@{
					Position = $position
					Variant  = $_.Variant.Name
					Round    = $_.Round
					Measured = $_.Measured
					Settings = if ($_.Variant.Overrides.Count -gt 0) { & $describeOverrides $_.Variant.Overrides } else { '' }
				}
			})
	}

	if (-not (Get-Command Open-Workspace -ErrorAction SilentlyContinue)) {
		Write-LogError "Open-Workspace is not available in this session." -NoLeadingNewline
		return
	}

	if ([string]::IsNullOrWhiteSpace($BenchmarkPath)) { $BenchmarkPath = Get-WorkspaceBenchmarkPath }
	if ([string]::IsNullOrWhiteSpace($ResultPath)) {
		$ResultPath = Join-Path -Path (Split-Path -Path $BenchmarkPath -Parent) -ChildPath 'WorkspaceOpenMeasurements.csv'
	}

	# ---- Configuration snapshot ------------------------------------------------------------------
	# Every key any variant touches, plus the benchmark opt-in, is restored in the finally block:
	# a key that was absent is removed again, not left behind as the last variant's value.
	$touchedKeys = [System.Collections.Generic.List[string]]::new()
	$touchedKeys.Add('WorkspaceBenchmark')
	foreach ($entry in $variants) {
		foreach ($key in $entry.Overrides.Keys) { if (-not $touchedKeys.Contains($key)) { $touchedKeys.Add($key) } }
	}
	$snapshot = @{}
	foreach ($key in $touchedKeys) {
		$snapshot[$key] = [PSCustomObject]@{ Present = $Configuration.ContainsKey($key); Value = $Configuration[$key] }
	}

	$applyVariant = {
		param($Entry)
		# Back to the snapshot first, so a key one variant sets and the next omits reads as the
		# original value in the next, not as the previous variant's.
		foreach ($key in $touchedKeys) {
			if ($key -eq 'WorkspaceBenchmark') { continue }
			if ($snapshot[$key].Present) { $Configuration[$key] = $snapshot[$key].Value } else { $Configuration.Remove($key) }
		}
		foreach ($key in $Entry.Overrides.Keys) { $Configuration[$key] = $Entry.Overrides[$key] }
	}

	$sessionId = [DateTimeOffset]::Now.ToString('yyyyMMdd-HHmmss', $invariant)
	$runRows = [System.Collections.Generic.List[pscustomobject]]::new()
	$benchmarkColumns = @(
		'Timestamp', 'Mode', 'Outcome', 'Attempts', 'TotalSeconds', 'ActionsSeconds', 'LayoutSeconds',
		'PreambleSeconds', 'DesktopsSeconds', 'FancyZonesSeconds', 'WaitSeconds', 'NormalizeSeconds',
		'PositionSeconds', 'SnapSeconds', 'VerifySeconds', 'RetrySeconds', 'SaveSeconds', 'OtherSeconds', 'Actions'
	)

	try {
		# Record every open, show nothing per open - the summary at the end is the display.
		$Configuration['WorkspaceBenchmark'] = @{ Enabled = $true; Display = 'None' }

		$position = 0
		foreach ($step in $schedule) {
			$position++
			$entry = $step.Variant
			$label = if ($step.Measured) { "round $($step.Round)" } else { 'warm-up' }
			Write-LogStep " Open $position/$($schedule.Count) => [$($entry.Name)] $label"

			& $applyVariant $entry

			try { $null = & $Teardown } catch { Write-LogWarning "Teardown failed before open $position => $($_.Exception.Message)" }
			if ($SettleSeconds -gt 0) { Start-Sleep -Seconds $SettleSeconds }

			$rowsBefore = @(Read-WorkspaceBenchmark -BenchmarkPath $BenchmarkPath).Count
			$clock = [System.Diagnostics.Stopwatch]::StartNew()
			$openError = $null
			try { Open-Workspace -Workspace $Workspace | Out-Null } catch { $openError = $_.Exception.Message }
			$clock.Stop()

			$benchmarkRow = $null
			try {
				$rowsAfter = @(Read-WorkspaceBenchmark -BenchmarkPath $BenchmarkPath)
				if ($rowsAfter.Count -gt $rowsBefore) {
					$benchmarkRow = @($rowsAfter | Select-Object -Skip $rowsBefore | Where-Object { $_.Workspace -eq $Workspace }) | Select-Object -Last 1
				}
			}
			catch { Write-LogWarning "Could not read the benchmark rows after open $position => $($_.Exception.Message)" }

			$row = [ordered]@{
				Session   = $sessionId
				Workspace = $Workspace
				Variant   = $entry.Name
				Round     = $step.Round
				Measured  = $step.Measured
				Position  = $position
				Settings  = if ($entry.Overrides.Count -gt 0) { & $describeOverrides $entry.Overrides } else { '' }
			}
			foreach ($key in $knownSettings.Keys) {
				$row[$key] = & $formatValue (& $effectiveSetting $key $Configuration)
			}
			foreach ($column in $benchmarkColumns) {
				$row[$column] = if ($benchmarkRow) { $benchmarkRow.$column } else { $null }
			}
			if (-not $benchmarkRow) {
				# No row means the open never reached its end (or the writer failed): keep the wall
				# clock we measured so the run is not lost, and say why in Outcome.
				$row['Outcome'] = if ($openError) { 'Error' } else { 'NoRow' }
				$row['Attempts'] = 0
				$row['TotalSeconds'] = [math]::Round($clock.Elapsed.TotalSeconds, 2)
				foreach ($column in $benchmarkColumns) { if ($null -eq $row[$column]) { $row[$column] = if ($column -like '*Seconds') { 0.0 } else { '' } } }
				$row['Timestamp'] = [DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm:ss', $invariant)
				$row['Mode'] = 'Plain'
				if ($openError) { $row['Actions'] = "Error=$openError" }
			}
			$rowObject = [PSCustomObject]$row
			$runRows.Add($rowObject)

			# Culture-invariant on disk, like the benchmark file itself.
			$csvRow = [ordered]@{}
			foreach ($key in $row.Keys) {
				$value = $row[$key]
				$csvRow[$key] = if ($value -is [double]) { $value.ToString('0.##', $invariant) } elseif ($value -is [int]) { $value.ToString($invariant) } elseif ($value -is [bool]) { $value.ToString() } else { [string]$value }
			}
			try {
				$directory = Split-Path -Path $ResultPath -Parent
				if ($directory -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop | Out-Null }
				[PSCustomObject]$csvRow | Export-Csv -LiteralPath $ResultPath -Append -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
			}
			catch { Write-LogWarning "Could not write the measurement row => $($_.Exception.Message)" }

			$outcomeNote = if ($rowObject.Outcome -ne 'Applied') { " ($($rowObject.Outcome))" } elseif ($rowObject.Attempts -gt 1) { " (retries $($rowObject.Attempts - 1))" } else { '' }
			Write-LogStep "   => $(([math]::Round([double]$rowObject.TotalSeconds, 1)).ToString('0.0', $invariant)) s$outcomeNote"
		}
	}
	finally {
		foreach ($key in $touchedKeys) {
			if ($snapshot[$key].Present) { $Configuration[$key] = $snapshot[$key].Value } else { $Configuration.Remove($key) }
		}
	}

	# ---- Summary --------------------------------------------------------------------------------
	$median = {
		param([double[]]$Values)
		$sorted = @($Values | Sort-Object)
		if ($sorted.Count -eq 0) { return 0.0 }
		$middle = [int][math]::Floor($sorted.Count / 2)
		$result = if ($sorted.Count % 2 -eq 1) { $sorted[$middle] } else { ($sorted[$middle - 1] + $sorted[$middle]) / 2 }
		return [math]::Round([double]$result, 2)
	}

	$measuredRows = @($runRows | Where-Object Measured)
	$summaries = foreach ($entry in $variants) {
		$items = @($measuredRows | Where-Object { $_.Variant -eq $entry.Name })
		if ($items.Count -eq 0) { continue }
		$clean = @($items | Where-Object { $_.Outcome -eq 'Applied' -and [int]$_.Attempts -eq 1 })
		$totals = [double[]]@($items | ForEach-Object { [double]$_.TotalSeconds })

		[PSCustomObject]@{
			Variant            = $entry.Name
			Runs               = $items.Count
			Clean              = $clean.Count
			Retries            = [int](@($items | ForEach-Object { [math]::Max(0, [int]$_.Attempts - 1) }) | Measure-Object -Sum).Sum
			NotApplied         = @($items | Where-Object { $_.Outcome -ne 'Applied' }).Count
			MedianTotal        = & $median $totals
			CleanMedianTotal   = & $median ([double[]]@($clean | ForEach-Object { [double]$_.TotalSeconds }))
			MinTotal           = [math]::Round(($totals | Measure-Object -Minimum).Minimum, 2)
			MaxTotal           = [math]::Round(($totals | Measure-Object -Maximum).Maximum, 2)
			MedianLayout       = & $median ([double[]]@($items | ForEach-Object { [double]$_.LayoutSeconds }))
			MedianFancyZones   = & $median ([double[]]@($items | ForEach-Object { [double]$_.FancyZonesSeconds }))
			MedianWait         = & $median ([double[]]@($items | ForEach-Object { [double]$_.WaitSeconds }))
			MedianPositionSnap = & $median ([double[]]@($items | ForEach-Object { [double]$_.PositionSeconds + [double]$_.SnapSeconds }))
			MedianVerify       = & $median ([double[]]@($items | ForEach-Object { [double]$_.VerifySeconds }))
			Settings           = if ($entry.Overrides.Count -gt 0) { & $describeOverrides $entry.Overrides } else { 'current configuration' }
		}
	}
	$summaries = @($summaries)

	if ($summaries.Count -gt 0) {
		$summaries | Format-Table -Property Variant, Runs, Clean, Retries, NotApplied, MedianTotal, CleanMedianTotal, MinTotal, MaxTotal, MedianLayout, MedianFancyZones, MedianWait, MedianPositionSnap, MedianVerify -AutoSize | Out-Host

		$ranked = @($summaries | Sort-Object -Property @{ Expression = 'CleanMedianTotal' }, @{ Expression = 'MedianTotal' })
		$fastest = @($ranked | Where-Object { $_.Clean -gt 0 }) | Select-Object -First 1
		if ($fastest) {
			$caveat = if ($fastest.Retries -gt 0 -or $fastest.NotApplied -gt 0) { " - but it needed $($fastest.Retries) retr$(if ($fastest.Retries -eq 1) { 'y' } else { 'ies' }) and $($fastest.NotApplied) run(s) did not end Applied" } else { '' }
			Write-LogSuccess "Fastest clean median: [$($fastest.Variant)] at $($fastest.CleanMedianTotal.ToString('0.0', $invariant)) s over $($fastest.Clean) clean run(s)$caveat"
		}
		Write-LogStep " Per-run rows => [$ResultPath] (session $sessionId)"
	}
	else {
		Write-LogWarning "No measured run produced a result."
	}

	if ($PassThru) {
		return [PSCustomObject]@{ Summary = $summaries; Runs = @($runRows) }
	}
	return $summaries
}
