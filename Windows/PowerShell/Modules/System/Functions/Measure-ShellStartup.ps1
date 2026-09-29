function Measure-ShellStartup {
	<#
	.SYNOPSIS
		Measures how long a shell takes to reach its first prompt, stage by stage: strip the
		profile to nothing, then add one startup stage at a time.

	.DESCRIPTION
		Starts child shells in the current console and times each one from launch to exit
		(Invoke-ShellStartupSample). The profile guards every startup stage with Test-StartupStage /
		Complete-StartupStage, so a child can be told which stages to leave out through
		WINUX_STARTUP_SKIP and reports what each stage cost inside the shell through
		WINUX_STARTUP_TRACE. Two ways to walk the stages:

		  Cumulative  (default) The first row is a bare `pwsh -NoProfile` - the floor no profile
		              can go under. The second is Core alone: the configuration load and the module
		              imports everything depends on. Every further row adds the next stage in
		              profile order. The Delta column is the wall time the added stage costs, the
		              InShell column what the stage measured for itself.
		  Isolated    The first row is the full start. Every further row is the full start with
		              exactly one stage skipped, so Delta is what that stage would save on its own,
		              which is the number a decision needs when stages interact (the first user of
		              a module pays its autoload, the next gets it free).

		Every configuration is run -Runs times (default 5) and reported as min / median / max;
		medians are what the deltas are computed from, because a single slow run - an antivirus
		scan, a disk wake - must not decide a stage's cost.

		The children share this console so what is measured is real: WT_SESSION, the interactive
		console and the terminal's cell-size reply are all inherited, and the image logo is
		rendered the way a new tab renders it. Two consequences: run this from the terminal whose
		start you want to measure (a Windows Terminal tab, in the directory a new tab opens in),
		and expect the screen to be cleared and redrawn once per child - the table is printed
		when every child has exited. Outside Windows Terminal a warning says the image-logo path
		is not part of what is being measured.

		The stage names are the ones the profile guards with Test-StartupStage:
		Schema, Greeting, FastfetchImageLogo, OnefetchStyle, PSReadLine, Terminal-Icons,
		PSReadLineOptions, OhMyPosh, Aliases, PowerPlan, LogMaintenance. Core is always present.
		FastfetchImageLogo and OnefetchStyle are the two opt-in decorations the all-hosts profile
		adds inside the greeting; listing them as stages of their own is what makes the image
		logo's cost visible separately from the panel's.

	.PARAMETER Runs
		Child shells per configuration. 1 to 50, default 5.

	.PARAMETER Mode
		Cumulative (strip, then add one at a time) or Isolated (full, then drop one at a time).

	.PARAMETER Stages
		The stages to walk, in the order to add them. Defaults to every guarded stage in profile
		order. Narrow it to re-measure a few stages quickly.

	.PARAMETER PassThru
		Also return the rows as objects (Configuration, Runs, Min, Median, Max, Delta, InShell).

	.OUTPUTS
		Nothing, or with -PassThru one [pscustomobject] per configuration.

	.EXAMPLE
		Measure-ShellStartup
		Bare shell, Core, then every stage added in order - 5 runs each - as one table.

	.EXAMPLE
		Measure-ShellStartup -Mode Isolated -Runs 3
		Full start, then the full start minus each stage in turn, 3 runs each.

	.EXAMPLE
		Measure-ShellStartup -Stages Greeting, FastfetchImageLogo -PassThru
		Bare, Core, Core + Greeting, Core + Greeting + image logo, returned as objects.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter()]
		[ValidateRange(1, 50)]
		[int]$Runs = 5,

		[Parameter()]
		[ValidateSet("Cumulative", "Isolated")]
		[string]$Mode = "Cumulative",

		[Parameter()]
		[ValidateNotNullOrEmpty()]
		[string[]]$Stages = @(
			"Schema", "Greeting", "FastfetchImageLogo", "OnefetchStyle", "PSReadLine", "Terminal-Icons",
			"PSReadLineOptions", "OhMyPosh", "Aliases", "PowerPlan", "LogMaintenance"
		),

		[Parameter()]
		[switch]$PassThru
	)

	Write-LogTitle "Shell Startup Measurement"

	if (-not $env:WT_SESSION) {
		Write-LogWarning "Not running inside Windows Terminal - the image logo and the terminal cell-size query are skipped by the greeting here, so their cost is not part of this measurement."
	}

	# The plan: one entry per configuration, in table order. Skip is what the child gets in
	# WINUX_STARTUP_SKIP; Stage names the stage the row is about, for the InShell column.
	$plan = [System.Collections.Generic.List[object]]::new()
	if ($Mode -eq "Cumulative") {
		$plan.Add([pscustomobject]@{ Configuration = "bare (-NoProfile)"; Skip = ""; Bare = $true; Stage = $null })
		$plan.Add([pscustomobject]@{ Configuration = "Core"; Skip = "All"; Bare = $false; Stage = "Core" })
		for ($i = 0; $i -lt $Stages.Count; $i++) {
			$remaining = @($Stages | Select-Object -Skip ($i + 1))
			$plan.Add([pscustomobject]@{ Configuration = "+ $($Stages[$i])"; Skip = ($remaining -join ","); Bare = $false; Stage = $Stages[$i] })
		}
	}
	else {
		$plan.Add([pscustomobject]@{ Configuration = "full"; Skip = ""; Bare = $false; Stage = $null })
		foreach ($stage in $Stages) {
			$plan.Add([pscustomobject]@{ Configuration = "- $stage"; Skip = $stage; Bare = $false; Stage = $stage })
		}
	}

	$totalRuns = $plan.Count * $Runs
	Write-LogStep " $Mode => $($plan.Count) configuration(s), $Runs run(s) each: $totalRuns shell starts. The screen is redrawn by every child; the table follows at the end."

	# Measure. Each row keeps its wall-time samples and, per stage, the in-shell samples.
	$rows = [System.Collections.Generic.List[object]]::new()
	foreach ($entry in $plan) {
		$wall = [System.Collections.Generic.List[double]]::new()
		$inShell = @{}
		for ($run = 1; $run -le $Runs; $run++) {
			$sample = if ($entry.Bare) { Invoke-ShellStartupSample -Bare } else { Invoke-ShellStartupSample -Skip $entry.Skip }
			$wall.Add([double]$sample.Milliseconds)
			foreach ($name in $sample.Stages.Keys) {
				if (-not $inShell.ContainsKey($name)) { $inShell[$name] = [System.Collections.Generic.List[double]]::new() }
				$inShell[$name].Add([double]$sample.Stages[$name])
			}
		}
		$rows.Add([pscustomobject]@{ Entry = $entry; Wall = $wall; InShell = $inShell })
	}

	# Median of a sample list: the middle value, or the mean of the two middle values.
	$median = {
		param([System.Collections.Generic.List[double]]$Values)
		if (-not $Values -or $Values.Count -eq 0) { return $null }
		$sorted = @($Values | Sort-Object)
		$mid = [int][math]::Floor($sorted.Count / 2)
		if ($sorted.Count % 2 -eq 1) { return [double]$sorted[$mid] }
		return ([double]$sorted[$mid - 1] + [double]$sorted[$mid]) / 2
	}

	# In Isolated mode the in-shell time of a stage comes from the full row, where it ran.
	$fullInShell = if ($Mode -eq "Isolated") { $rows[0].InShell } else { $null }

	$results = [System.Collections.Generic.List[object]]::new()
	$previousMedian = $null
	$fullMedian = $null
	foreach ($row in $rows) {
		$rowMedian = & $median $row.Wall
		if ($null -eq $fullMedian) { $fullMedian = $rowMedian }

		$delta = $null
		if ($Mode -eq "Cumulative") {
			if ($null -ne $previousMedian) { $delta = $rowMedian - $previousMedian }
		}
		elseif ($row.Entry.Stage) {
			$delta = $rowMedian - $fullMedian
		}

		$stageSamples = $null
		if ($row.Entry.Stage) {
			$source = if ($fullInShell) { $fullInShell } else { $row.InShell }
			if ($source.ContainsKey($row.Entry.Stage)) { $stageSamples = $source[$row.Entry.Stage] }
		}
		$stageMedian = & $median $stageSamples

		$results.Add([pscustomobject]@{
				Configuration = $row.Entry.Configuration
				Runs          = $row.Wall.Count
				Min           = [math]::Round(($row.Wall | Measure-Object -Minimum).Minimum, 0)
				Median        = [math]::Round($rowMedian, 0)
				Max           = [math]::Round(($row.Wall | Measure-Object -Maximum).Maximum, 0)
				Delta         = if ($null -ne $delta) { [math]::Round($delta, 0) } else { $null }
				InShell       = if ($null -ne $stageMedian) { [math]::Round($stageMedian, 0) } else { $null }
			})
		$previousMedian = $rowMedian
	}

	$invariant = [cultureinfo]::InvariantCulture
	$header = "{0,-24} {1,5} {2,8} {3,8} {4,8} {5,8} {6,8}" -f "Configuration", "Runs", "Min", "Median", "Max", "Delta", "InShell"
	Write-LogStep " $header"
	foreach ($result in $results) {
		$deltaText = if ($null -ne $result.Delta) { ("{0:+#;-#;0}" -f $result.Delta) } else { "" }
		$inShellText = if ($null -ne $result.InShell) { $result.InShell.ToString($invariant) } else { "" }
		$line = "{0,-24} {1,5} {2,8} {3,8} {4,8} {5,8} {6,8}" -f $result.Configuration, $result.Runs, $result.Min, $result.Median, $result.Max, $deltaText, $inShellText
		Write-LogStep " $line" -NoLeadingNewline
	}
	Write-LogStep " All values in milliseconds. Delta => $(if ($Mode -eq 'Cumulative') { 'median minus the previous row: what the added stage costs in wall time' } else { 'median minus the full start: negative is what skipping the stage saves' }). InShell => the stage's own median as the profile measured it."

	if ($PassThru) { return $results }
}
