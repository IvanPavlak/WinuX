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

		The workspace defaults to Example, which ships with WinuX (WorkspaceActions and its layout
		files), so the experiment runs on a fresh install without anything defined first. Any
		configured workspace works; one whose Open-Project action needs a project takes it
		positionally, like Open-Workspace does ("Measure-WorkspaceOpen Client Asseto"), and
		anything further on the command line is forwarded to Open-Workspace unchanged.

		Which variants run:
		  - Without -Variant, the one-factor-at-a-time set over -Setting (all three layout flags by
		    default): the current configuration as "Baseline", plus one variant per setting with
		    ONLY that setting flipped. Four opens per round for the three flags.
		  - -FullFactorial instead runs every combination of the -Setting values (2^n variants).
		  - -Variant runs exactly the hashtables given. Every key is a configuration key and its
		    value is what the run gets; an optional Name key labels the variant. Any key works, not
		    only the three layout flags, so a delay or a retry count can be compared the same way.

		Every measured run is appended to WorkspaceOpenMeasurements.csv beside the benchmark file
		(Get-WorkspaceOpenMeasurementPath): the session id, variant name, round, the project, the
		three layout flags as they were in effect, the variant's own overrides, and the whole
		benchmark row. Nothing is thrown away - a run whose open produced no benchmark row is
		recorded with Outcome NoRow, one that threw with Error. The benchmark rows the opens append
		to WorkspaceBenchmark.csv carry Source "Measure-WorkspaceOpen <session>", so
		Get-WorkspaceBenchmark leaves them out of the everyday history unless asked
		(-IncludeMeasured).

		The result is one summary per variant, printed as a table and returned as objects
		(ConvertTo-WorkspaceOpenSummary): the number of measured runs, how many ended Applied on the
		first attempt, the retries, the median/min/max total, the medians of the phases the flags
		control (Layout, FancyZones, Wait, Position+Snap, Verify), the median total over the clean
		runs only, and - against the first variant - Effect (seconds, negative is faster), Spread
		(the variant's own clean-run range) and a Verdict: Noise when the effect is inside the
		within-variant scatter, Faster or Slower otherwise. Medians, not averages - one 40-second
		outlier must not decide the experiment. Read Retries and Applied before the seconds: a
		variant that wins the median by needing a retry every third run has not won. The table can
		be replayed later with Get-WorkspaceOpenMeasurement -Session <id>.

		Refuses to run a workspace whose actions include Terminate-WindowsTerminalTabs -OnlyCurrent
		or -IncludeCurrent, because that action ends the calling process and would end the
		experiment with it, and a workspace whose Open-Project action has no project when -Project
		was not given, because every open would stop at the project menu. -MaxMinutes stops
		scheduling new opens once the budget is spent and summarizes what ran. -DryRun prints the
		plan (variants, order, opens) and changes nothing.

	.PARAMETER Workspace
		The workspace to open. Must be configured in WorkspaceActions. Example by default - the
		workspace that ships with WinuX.

	.PARAMETER Project
		Project name(s) handed to Open-Workspace -Project, so a workspace whose Open-Project action
		would otherwise show a selection menu opens the same project(s) on every run without a
		prompt. Positional, like in Open-Workspace: "Measure-WorkspaceOpen Client Asseto".

	.PARAMETER ExtraArgs
		Everything else on the command line is forwarded to Open-Workspace unchanged, which
		forwards it to the actions that declare the parameter - the same way
		"Open-Workspace Client Asseto run" does. The values are not varied between runs.

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

	.PARAMETER MaxMinutes
		Time budget for the whole experiment. Once it is spent no further open is started; the
		opens that ran are summarized and the ones that did not are reported. 0 (no budget) by
		default.

	.PARAMETER DryRun
		Print the plan and return it without opening, tearing down or touching the configuration.

	.PARAMETER ResultPath
		Write the per-run rows to a different file. Defaults to Get-WorkspaceOpenMeasurementPath.

	.PARAMETER BenchmarkPath
		Read the benchmark rows from a different file. Defaults to Get-WorkspaceBenchmarkPath.

	.PARAMETER Configuration
		The configuration hashtable to modify and restore. Defaults to $global:Configuration, the
		one Open-Workspace and Set-WorkspaceWindowLayout read.

	.PARAMETER PassThru
		Return the per-run rows in addition to the summary, as the Runs property of a single
		result object with Session, Summary and Runs.

	.EXAMPLE
		Measure-WorkspaceOpen
		# The shipped Example workspace: 1 warm-up, then 5 rounds of Baseline + each layout flag flipped alone (21 opens).

	.EXAMPLE
		Measure-WorkspaceOpen Client Asseto
		# A workspace whose Open-Project action needs a project: every open gets Asseto, no menu.

	.EXAMPLE
		Measure-WorkspaceOpen WinuX -Setting FancyZonesApplyMethod -Runs 8
		# Only File against Hotkeys, 8 measured opens each, interleaved.

	.EXAMPLE
		Measure-WorkspaceOpen WinuX -FullFactorial -Runs 3 -MaxMinutes 30
		# All 8 combinations of the three flags, 3 opens each, but stop starting opens after half an hour.

	.EXAMPLE
		Measure-WorkspaceOpen WinuX -Variant @{ Name = 'Current' }, @{ Name = 'AllOff'; FancyZonesApplyMethod = 'Hotkeys'; WorkspaceLayoutPipelining = $false; WorkspaceLayoutPrepareEarly = $false }

	.EXAMPLE
		Measure-WorkspaceOpen WinuX -DryRun
		# Shows what would run, in which order, and how many opens that is.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Position = 0)]
		[string]$Workspace = 'Example',

		[Parameter(Position = 1)]
		[string[]]$Project,

		[Parameter(ValueFromRemainingArguments = $true)]
		[object[]]$ExtraArgs,

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
		[ValidateRange(0, 1440)]
		[double]$MaxMinutes = 0,

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
		$configured = if ($Configuration.WorkspaceActions) { @($Configuration.WorkspaceActions.Keys | Sort-Object) -join ', ' } else { 'none' }
		Write-LogError "Workspace [$Workspace] is not configured in WorkspaceActions (configured: $configured)." -NoLeadingNewline
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

	# An Open-Project action with no project of its own asks for one at a menu, and the
	# experiment would stall there on every open unless -Project supplies it.
	if (-not $Project) {
		foreach ($action in @($workspaceActions)) {
			if ($action.Action -ne 'Open-Project') { continue }
			$parameters = $action.Parameters
			$hasProject = $parameters -and $parameters.ContainsKey('Project') -and -not [string]::IsNullOrWhiteSpace([string]($parameters['Project'] -join ''))
			if (-not $hasProject) {
				Write-LogError "Workspace [$Workspace] has an Open-Project action without a project, so every open would stop at the project menu - pass the project: Measure-WorkspaceOpen $Workspace <Project>." -NoLeadingNewline
				return
			}
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

	$openLabel = $Workspace
	if ($Project) { $openLabel += " -Project $($Project -join ', ')" }
	if ($ExtraArgs) { $openLabel += " $($ExtraArgs -join ' ')" }
	$budgetLabel = if ($MaxMinutes -gt 0) { ", $($MaxMinutes.ToString('0.##', $invariant)) minute budget" } else { '' }
	Write-LogStep " Workspace [$openLabel] => $($variants.Count) variant(s), $Runs run(s) each, $WarmUp warm-up(s): $($schedule.Count) opens, $Order order$budgetLabel"
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

	# The same open every time: the workspace, the project(s) and whatever else was on the
	# command line, exactly as Open-Workspace would have received them when typed directly.
	$openArguments = @{ Workspace = $Workspace }
	if ($Project) { $openArguments['Project'] = $Project }
	$openExtraArgs = @($ExtraArgs)

	$sessionId = [DateTimeOffset]::Now.ToString('yyyyMMdd-HHmmss', $invariant)
	# Stamped on every benchmark row the opens append, so the everyday history can leave the
	# experiment's rows out (Get-WorkspaceBenchmark) and this loop can pick its own row back up.
	$sourceTag = "Measure-WorkspaceOpen $sessionId"
	$runRows = [System.Collections.Generic.List[pscustomobject]]::new()
	$benchmarkColumns = @(
		'Timestamp', 'Mode', 'Outcome', 'Attempts', 'TotalSeconds', 'ActionsSeconds', 'LayoutSeconds',
		'PreambleSeconds', 'DesktopsSeconds', 'FancyZonesSeconds', 'WaitSeconds', 'NormalizeSeconds',
		'PositionSeconds', 'SnapSeconds', 'VerifySeconds', 'RetrySeconds', 'SaveSeconds', 'OtherSeconds', 'Actions'
	)
	$experimentClock = [System.Diagnostics.Stopwatch]::StartNew()
	$skippedForBudget = 0

	try {
		# Record every open, show nothing per open - the summary at the end is the display.
		$Configuration['WorkspaceBenchmark'] = @{ Enabled = $true; Display = 'None'; Source = $sourceTag }

		$position = 0
		foreach ($step in $schedule) {
			$position++

			# The budget is checked before an open starts, never in the middle of one: the open
			# that is running always finishes and is recorded.
			if ($MaxMinutes -gt 0 -and $position -gt 1 -and $experimentClock.Elapsed.TotalMinutes -ge $MaxMinutes) {
				$skippedForBudget = $schedule.Count - $position + 1
				Write-LogWarning "Time budget of $($MaxMinutes.ToString('0.##', $invariant)) minute(s) spent after $($position - 1) of $($schedule.Count) opens - the remaining $skippedForBudget did not run."
				break
			}

			$entry = $step.Variant
			$label = if ($step.Measured) { "round $($step.Round)" } else { 'warm-up' }
			Write-LogStep " Open $position/$($schedule.Count) => [$($entry.Name)] $label"

			& $applyVariant $entry

			try { $null = & $Teardown } catch { Write-LogWarning "Teardown failed before open $position => $($_.Exception.Message)" }
			if ($SettleSeconds -gt 0) { Start-Sleep -Seconds $SettleSeconds }

			$rowsBefore = @(Read-WorkspaceBenchmark -BenchmarkPath $BenchmarkPath).Count
			$clock = [System.Diagnostics.Stopwatch]::StartNew()
			$openError = $null
			try { Open-Workspace @openArguments @openExtraArgs | Out-Null } catch { $openError = $_.Exception.Message }
			$clock.Stop()

			$benchmarkRow = $null
			try {
				$rowsAfter = @(Read-WorkspaceBenchmark -BenchmarkPath $BenchmarkPath)
				if ($rowsAfter.Count -gt $rowsBefore) {
					# Only the rows this open appended, for this workspace, and - when the writer
					# stamped one - carrying this session's tag.
					$benchmarkRow = @($rowsAfter | Select-Object -Skip $rowsBefore | Where-Object {
							$_.Workspace -eq $Workspace -and ([string]::IsNullOrEmpty([string]$_.Source) -or [string]$_.Source -eq $sourceTag)
						}) | Select-Object -Last 1
				}
			}
			catch { Write-LogWarning "Could not read the benchmark rows after open $position => $($_.Exception.Message)" }

			$row = [ordered]@{
				Session   = $sessionId
				Workspace = $Workspace
				Project   = ($Project -join ' ')
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
	# Shared with Get-WorkspaceOpenMeasurement, so the table replayed from the file later is the
	# table printed here. The reference is the first variant - Baseline in the default set.
	$summaries = @(ConvertTo-WorkspaceOpenSummary -Row @($runRows) -Reference $variants[0].Name)

	if ($summaries.Count -gt 0) {
		$summaries | Format-Table -Property Variant, Runs, Clean, Retries, NotApplied, MedianTotal, CleanMedianTotal, MinTotal, MaxTotal, Effect, Spread, Verdict, MedianLayout, MedianFancyZones, MedianWait, MedianPositionSnap, MedianVerify -AutoSize | Out-Host

		$ranked = @($summaries | Sort-Object -Property @{ Expression = 'CleanMedianTotal' }, @{ Expression = 'MedianTotal' })
		$fastest = @($ranked | Where-Object { $_.Clean -gt 0 }) | Select-Object -First 1
		if ($fastest) {
			$caveat = if ($fastest.Retries -gt 0 -or $fastest.NotApplied -gt 0) { " - but it needed $($fastest.Retries) retr$(if ($fastest.Retries -eq 1) { 'y' } else { 'ies' }) and $($fastest.NotApplied) run(s) did not end Applied" } else { '' }
			Write-LogSuccess "Fastest clean median: [$($fastest.Variant)] at $($fastest.CleanMedianTotal.ToString('0.0', $invariant)) s over $($fastest.Clean) clean run(s)$caveat"
		}

		$compared = @($summaries | Where-Object { $_.Verdict -ne 'Reference' })
		if ($compared.Count -gt 0) {
			$noise = @($compared | Where-Object { $_.Verdict -eq 'Noise' })
			$reference = @($summaries | Where-Object { $_.Verdict -eq 'Reference' })[0]
			if ($noise.Count -eq $compared.Count) {
				Write-LogStep " Verdict => every variant is within the noise of [$($reference.Variant)]: the differences are smaller than the spread between opens of the same configuration. More runs per variant would be needed to see anything finer."
			}
			else {
				$decided = @($compared | Where-Object { $_.Verdict -ne 'Noise' } | ForEach-Object { "[$($_.Variant)] $($_.Verdict.ToLower()) by $([math]::Abs($_.Effect).ToString('0.0', $invariant)) s" })
				Write-LogStep " Verdict => $($noise.Count) of $($compared.Count) variant(s) within the noise of [$($reference.Variant)]; $($decided -join ', ')"
			}
		}
		if ($skippedForBudget -gt 0) {
			Write-LogWarning "Partial experiment: $skippedForBudget planned open(s) did not run because of -MaxMinutes - the variants may have unequal run counts."
		}
		Write-LogStep " Per-run rows => [$ResultPath] (session $sessionId; replay with Get-WorkspaceOpenMeasurement -Session $sessionId -Formatted)"
	}
	else {
		Write-LogWarning "No measured run produced a result."
	}

	if ($PassThru) {
		return [PSCustomObject]@{ Session = $sessionId; Summary = $summaries; Runs = @($runRows) }
	}
	return $summaries
}
