<#
.SYNOPSIS
	Runs the Pester suite across parallel, process-isolated workers and writes one run log.

.DESCRIPTION
	The single source of truth for running this repository's tests, locally and in CI. Run-Tests
	is a thin wrapper around it; the Tests workflow calls it directly with -CI.

	Pester (6.x included) has no native parallelism, so the harness provides it: the discovered *.Tests.ps1
	files are bucketed by expected duration and handed to N child `pwsh -NoProfile` processes,
	each of which bootstraps its own hermetic session (the same bootstrap the CI job used to
	inline) and runs Invoke-Pester over its own bucket. Because every worker is a separate
	process, the tests cannot pollute the calling session - no profile reload afterwards - and
	one crashed worker cannot take the run down silently.

	Terminal output is deliberately minimal: a spinner with a live test counter, then a one-line
	verdict and the path to the run log. The counter's denominator is read off the test files'
	syntax trees (Get-ExpectedTestCount.ps1, beside this script) while the workers bootstrap, so
	it is the total for the files about to run, not the previous run's. Everything a serial `Invoke-Pester -Verbosity Detailed`
	would have printed - every per-test line and everything the code under test writes to the
	console - is captured per worker and merged into Results\TestRun_<stamp>_<PID>.log, alongside
	the per-worker NUnit XMLs. Every artifact is named after the run that produced it, so two
	concurrent runs cannot overwrite or misreport each other. Results\ is gitignored, exactly
	like the Logging module's Logs\.

	Speed comes from removing waste first and running less second. The worker count is learned
	per machine from earlier green full runs; files with no timing yet are seeded by their test
	count (an Integration file by a heavy fixed seed); the run log records the machine's
	conditions and each worker's start-up, so a slow run explains itself. -Quick leaves out the
	Integration tier and -Changed runs only what the changes can affect - both conveniences, while
	the bare run and -CI always run everything, and every green full run stamps the tree it proved.

	The helpers live beside this script as plain dot-sourced files (Get-*.ps1, Read-*.ps1, ...)
	for the same reason this is a script: CI runs it with no WinuX module loaded.

	This script is intentionally NOT in Functions\ - Tests.psm1 dot-sources and exports every
	file there, and this is a script, not an exported function. It also deliberately uses plain
	Write-Host rather than Write-Log*: CI runs it before any WinuX module exists in the session.

.PARAMETER TestName
	Filter to files matching *<TestName>*.Tests.ps1. Several patterns run the union of their
	matches; a file matched by more than one runs once. Omit to run everything discovered.

.PARAMETER Path
	Root to discover tests under. Defaults to this module's own directory, and additionally
	sweeps the fork-owned Custom area (Modules\Custom\<Module>\Tests) when no -Path is given.

.PARAMETER Workers
	Number of parallel worker processes. An explicit value always wins and is never learned from.
	0 (default) lets the learner pick (Get-AdaptiveWorkerCount over Results\workers.json); -CI
	uses the static min(CPU count, 12).

.PARAMETER Detailed
	Echo the whole run log - including every worker transcript - to the console after the run.

.PARAMETER CI
	Non-interactive mode: no spinner, plain progress lines, the run summary echoed to stdout,
	and "no test files found" treated as an infrastructure failure rather than a warning. CI
	always runs everything: -Quick and -Changed are ignored, and no history is read or written.

.PARAMETER PassThru
	Emit the aggregate result object.

.PARAMETER Quick
	Leave out the Integration tier: files whose tests are all tagged Integration are not
	dispatched, and the others run with Pester's ExcludeTag. Never the gate.

.PARAMETER Changed
	Run only the test files the changes since -Since can affect (Get-ChangedPaths, Get-TestImpact),
	conservatively; the selection and its reasons are printed first. Unions with -TestName/-Path.

.PARAMETER Since
	The ref -Changed compares against (its merge base with HEAD). Defaults to master. With -CI it
	does not narrow the run; it adds the selector audit (what -Changed would have run vs. what failed).

.PARAMETER BuildImpactMap
	Full run that records, per test file, which functions it invoked (Results\impact-map.json),
	the runtime backstop -Changed unions with its static analysis. About twice as slow.

.PARAMETER Worker
	Internal. Marks this invocation as a worker child; not for interactive use.

.PARAMETER FileListPath
	Internal. Response file holding one test-file path per line for this worker's bucket.

.PARAMETER ResultXmlPath
	Internal. Where this worker writes its NUnit3 XML.

.PARAMETER SummaryJsonPath
	Internal. Where this worker writes its machine-readable run summary.

.PARAMETER WorkerId
	Internal. Zero-based index of this worker, used to label its artifacts.

.PARAMETER ExcludeTag
	Internal. Tags this worker's Pester run excludes (comma-joined).

.PARAMETER ImpactMapPath
	Internal. Run each file separately under command breakpoints and write which functions it
	invoked here.

.EXAMPLE
	.\Invoke-TestSuite.ps1
	Runs the whole suite on the default worker count.

.EXAMPLE
	.\Invoke-TestSuite.ps1 -TestName Open-Terminal -Workers 2
	Runs only *Open-Terminal*.Tests.ps1 on two workers.

.EXAMPLE
	.\Invoke-TestSuite.ps1 -TestName Open-Terminal, Close-Workspace
	Runs every file matching either pattern.

.EXAMPLE
	.\Invoke-TestSuite.ps1 -CI
	The CI entry point: no spinner, summary on stdout, infrastructure failures exit 2.

.EXAMPLE
	.\Invoke-TestSuite.ps1 -Changed -Quick
	Only the files the branch's changes can affect, without the Integration tier.

.EXAMPLE
	.\Invoke-TestSuite.ps1 -CI -Since origin/master
	The full suite, plus the selector audit against the PR's base.

.NOTES
	Exit codes: 0 = all tests passed, 1 = test failures, 2 = infrastructure failure (bootstrap
	failed, Pester missing, a worker died without writing its summary, a bucket ran fewer
	containers than it was assigned, or -CI matched no test files). A silently unrun file must
	never be able to green the gate.
#>

[CmdletBinding(DefaultParameterSetName = 'Orchestrate')]
param(
	[Parameter(ParameterSetName = 'Orchestrate', Position = 0)]
	[string[]]$TestName,

	[Parameter(ParameterSetName = 'Orchestrate')]
	[string]$Path,

	[Parameter(ParameterSetName = 'Orchestrate')]
	[int]$Workers = 0,

	[Parameter(ParameterSetName = 'Orchestrate')]
	[switch]$Detailed,

	[Parameter(ParameterSetName = 'Orchestrate')]
	[switch]$CI,

	[Parameter(ParameterSetName = 'Orchestrate')]
	[switch]$PassThru,

	[Parameter(ParameterSetName = 'Orchestrate')]
	[switch]$Quick,

	[Parameter(ParameterSetName = 'Orchestrate')]
	[switch]$Changed,

	[Parameter(ParameterSetName = 'Orchestrate')]
	[string]$Since,

	[Parameter(ParameterSetName = 'Orchestrate')]
	[switch]$BuildImpactMap,

	[Parameter(ParameterSetName = 'Worker', Mandatory = $true)]
	[switch]$Worker,

	[Parameter(ParameterSetName = 'Worker', Mandatory = $true)]
	[string]$FileListPath,

	[Parameter(ParameterSetName = 'Worker', Mandatory = $true)]
	[string]$ResultXmlPath,

	[Parameter(ParameterSetName = 'Worker', Mandatory = $true)]
	[string]$SummaryJsonPath,

	[Parameter(ParameterSetName = 'Worker')]
	[int]$WorkerId = 0,

	[Parameter(ParameterSetName = 'Worker')]
	[string[]]$ExcludeTag = @(),

	[Parameter(ParameterSetName = 'Worker')]
	[string]$ImpactMapPath
)

$ProgressPreference = 'SilentlyContinue'

# The modules a worker session needs before any test runs. Tests Mock cross-module commands
# (Write-LogTitle, Resolve-Selection, Start-Application, ...), and Pester can only mock a
# command it can resolve - so these must be importable first or the mocks fail with
# "Could not find Command". This list is the whole session contract.
$script:BootstrapModules = @('Logging', 'Helper', 'System', 'AI', 'Application', 'Git', 'Window', 'Workflow', 'Configuration', 'Bootstrap')

# Files that touch state shared across processes and therefore may not run concurrently with
# each other: Set-WorkspaceWindowLayout's tests write real User-scope WORKSPACE_* variables and
# Reset-KeyboardModifiers' tests inject real keystrokes. Everything else was checked to be
# per-process (Process-scope env vars, $TestDrive, mocked registry writes). They are pinned into
# the same bucket, which keeps them serialized relative to one another.
$script:SerializedFiles = @('Set-WorkspaceWindowLayout.Tests.ps1', 'Reset-KeyboardModifiers.Tests.ps1')

# Repository layout. This script has to resolve its own repo with zero WinuX modules loaded
# (that is exactly the state CI runs it in), so it inlines the upward walk that
# Get-RepositoryPath performs rather than depending on the Helper module.
$script:PowerShellRoot = $PSScriptRoot
while ($script:PowerShellRoot -and -not (Test-Path -LiteralPath (Join-Path $script:PowerShellRoot 'Configuration.psd1'))) {
	$script:PowerShellRoot = Split-Path -Path $script:PowerShellRoot -Parent
}
if (-not $script:PowerShellRoot) {
	Write-Host -ForegroundColor Red "`n=> Invoke-TestSuite: could not locate Configuration.psd1 in any parent of [$PSScriptRoot]."
	exit 2
}

$script:ModulesRoot = Join-Path -Path $script:PowerShellRoot -ChildPath 'Modules'
$script:CustomRoot = Join-Path -Path $script:ModulesRoot -ChildPath 'Custom'
$script:ResultsRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Results'
$script:TimingsFile = Join-Path -Path $script:ResultsRoot -ChildPath 'timings.json'

# Every artifact a run produces is named after that run: stamp plus orchestrator PID, the same
# shape the Logging module uses for Session_<stamp>_<PID>.log. Two runs at once are entirely
# ordinary - a scoped Run-Tests in one terminal while a full sweep finishes in another - and with
# fixed filenames they trampled each other: the second run wiped the first's in-flight worker
# files and then read a summary JSON the first run's worker had written, reporting results it
# never produced. Per-run names make concurrent runs simply not see each other.
$script:RunId = "{0}_{1}" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'), $PID
$script:WorkRoot = Join-Path -Path (Join-Path -Path $script:ResultsRoot -ChildPath 'Work') -ChildPath $script:RunId

# | ------------------------------ < Worker Role > ------------------------------ | #

if ($PSCmdlet.ParameterSetName -eq 'Worker') {
	$ErrorActionPreference = 'Stop'

	# The child's console defaults to the OEM code page; force UTF-8 so the transcript the
	# orchestrator merges (and reads for the live counter) round-trips non-ASCII output.
	try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() } catch { }

	$workerStart = Get-Date
	$summary = [ordered]@{
		worker         = $WorkerId
		processId      = $PID
		pesterVersion  = $null
		startedAt      = $workerStart.ToString('o')
		testsStartedAt = $null
		endedAt        = $null
		durationSec    = 0.0
		assignedFiles  = 0
		counts         = [ordered]@{ total = 0; passed = 0; failed = 0; skipped = 0; notRun = 0 }
		containers     = @()
		failures       = @()
		bootstrapError = $null
	}

	# Written on every exit path, including bootstrap failure: a missing summary is how the
	# orchestrator detects a worker that died, so an empty-but-valid one must never be skipped.
	$writeSummary = {
		$summary.endedAt = (Get-Date).ToString('o')
		$summary.durationSec = [math]::Round(((Get-Date) - $workerStart).TotalSeconds, 2)
		try {
			$json = $summary | ConvertTo-Json -Depth 6
			[System.IO.File]::WriteAllText($SummaryJsonPath, $json, [System.Text.UTF8Encoding]::new($false))
		}
		catch {
			Write-Host "Worker ${WorkerId}: failed to write summary JSON => $($_.Exception.Message)"
		}
	}

	try {
		$separator = [System.IO.Path]::PathSeparator
		$env:PSModulePath = $script:ModulesRoot + $separator + $env:PSModulePath
		$hasCustom = Test-Path -LiteralPath $script:CustomRoot
		if ($hasCustom) {
			$env:PSModulePath = $env:PSModulePath + $separator + $script:CustomRoot
		}

		$global:Configuration = Import-PowerShellDataFile -Path (Join-Path $script:PowerShellRoot 'Configuration.psd1')

		# File logging off before the first import. Otherwise every worker opens its own
		# Session_*.log and they all append to the one shared Errors.log, paying an
		# Add-Content per Write-Log call for output nobody reads - the worker transcript
		# already captures all of it. Logging tests that need file logging build their own
		# $global:LoggingState against $TestDrive, so they are unaffected.
		if ($global:Configuration.Logging -and $global:Configuration.Logging.FileLogging) {
			$global:Configuration.Logging.FileLogging.Enabled = $false
		}

		foreach ($module in $script:BootstrapModules) {
			Import-Module -Name $module -Force -Global -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
		}
		if ($hasCustom) {
			Import-Module -Name 'Custom' -Force -Global -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
		}
		if (-not (Get-Command -Name 'Get-RepositoryPath' -ErrorAction SilentlyContinue)) {
			throw "session bootstrap failed - Get-RepositoryPath is missing after importing $($script:BootstrapModules -join ', ')."
		}

		# Build the logging state NOW, while the configuration above still says file logging is
		# off. Left to the first Write-Log call, it was built from whatever configuration the test
		# making that call had swapped in - usually one with no Logging section, where file logging
		# defaults to on - and the worker then paid a session-log append per line for the rest of
		# its bucket.
		if (Get-Command -Name 'Initialize-LoggingState' -ErrorAction SilentlyContinue) {
			Initialize-LoggingState -Force | Out-Null
		}

		try {
			# Pinned repo-wide: RequiredPesterVersion.txt is the single source of truth this
			# harness, Install-PowerShellModules, and CI all read. -RequiredVersion (exact), not
			# -MinimumVersion: Pester installs side-by-side, so exactness costs nothing and a
			# machine with the wrong version fails loudly here instead of drifting silently.
			$requiredPesterVersion = (Get-Content -LiteralPath (Join-Path (Get-RepositoryPath).Modules "Tests\RequiredPesterVersion.txt")).Trim()
			Import-Module -Name Pester -RequiredVersion $requiredPesterVersion -ErrorAction Stop
		}
		catch {
			throw "Pester $requiredPesterVersion is not available. Please run Install-PowerShellModules first. ($($_.Exception.Message))"
		}
		$summary.pesterVersion = (Get-Module -Name Pester | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString()
	}
	catch {
		$summary.bootstrapError = $_.Exception.Message
		Write-Host "Worker ${WorkerId}: bootstrap failed => $($_.Exception.Message)"
		& $writeSummary
		exit 2
	}

	$assigned = @(Get-Content -LiteralPath $FileListPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
	$summary.assignedFiles = $assigned.Count

	# Arrives as one comma-joined string: pwsh -File does not parse array syntax.
	$ExcludeTag = @($ExcludeTag | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

	# NOTE: this must never be named $Configuration - it would shadow the $global:Configuration
	# that the functions under test read through the unqualified name, and tests would fail in
	# ways that point nowhere near here.
	$newPesterConfiguration = {
		param([string[]]$RunPath, [bool]$WriteResult)
		$pesterConfiguration = New-PesterConfiguration
		$pesterConfiguration.Run.Path = $RunPath
		$pesterConfiguration.Run.PassThru = $true
		# Detailed on purpose: this stream is redirected to the worker's transcript, never to the
		# terminal, and its one line per finished test is what the orchestrator counts to drive the
		# live counter.
		$pesterConfiguration.Output.Verbosity = 'Detailed'
		$pesterConfiguration.Output.RenderMode = 'Plaintext'
		$pesterConfiguration.TestResult.Enabled = $WriteResult
		$pesterConfiguration.TestResult.OutputFormat = 'NUnit3'
		$pesterConfiguration.TestResult.OutputPath = $ResultXmlPath
		if ($ExcludeTag.Count -gt 0) {
			$pesterConfiguration.Filter.ExcludeTag = [string[]]$ExcludeTag
		}
		$pesterConfiguration
	}

	# The end of this worker's start-up: the orchestrator subtracts its spawn time from this to
	# report how long start-up took, which is what explodes when the machine is contended.
	# Unix milliseconds rather than a date string: ConvertFrom-Json turns ISO strings back into
	# dates in whatever kind it likes, and a time-zone slip would read as hours of start-up.
	$summary.testsStartedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

	$results = [System.Collections.Generic.List[object]]::new()
	if ($ImpactMapPath) {
		# -BuildImpactMap: which functions each test file actually invokes. A command breakpoint on
		# every function (Logging excluded - a Logging change runs everything anyway) adds the name
		# to a set; the files run one Invoke-Pester at a time so each set belongs to one file. Mocked
		# functions count as invoked, which can only make the map select more, never less. A function
		# that reads $? is left out: a breakpoint action runs just before the function and resets $?,
		# which would change what it sees. Its own tests are still selected by name and reference.
		$impactNames = @(
			foreach ($moduleRoot in @($script:ModulesRoot, $script:CustomRoot)) {
				foreach ($moduleDirectory in @(Get-ChildItem -LiteralPath $moduleRoot -Directory -ErrorAction SilentlyContinue)) {
					if ($moduleDirectory.Name -in 'Logging', 'Custom') { continue }
					$functionsDirectory = Join-Path $moduleDirectory.FullName 'Functions'
					if (-not (Test-Path -LiteralPath $functionsDirectory)) { continue }
					foreach ($functionFile in @(Get-ChildItem -LiteralPath $functionsDirectory -Filter '*.ps1' -File)) {
						if (-not ([System.IO.File]::ReadAllText($functionFile.FullName).Contains('$?'))) { $functionFile.BaseName }
					}
				}
			}
		) | Sort-Object -Unique
		$global:WinuXImpactHits = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
		$impactBreakpoints = @(Set-PSBreakpoint -Command $impactNames -Action { [void]$global:WinuXImpactHits.Add($_.Command) })
		$impact = [ordered]@{}
		try {
			foreach ($file in $assigned) {
				$global:WinuXImpactHits.Clear()
				$results.Add((Invoke-Pester -Configuration (& $newPesterConfiguration @($file) $false)))
				$impact[$file] = @($global:WinuXImpactHits | Sort-Object)
			}
		}
		finally {
			$impactBreakpoints | Remove-PSBreakpoint -ErrorAction SilentlyContinue
		}
		try { [System.IO.File]::WriteAllText($ImpactMapPath, ($impact | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false)) }
		catch { Write-Host "Worker ${WorkerId}: failed to write the impact map => $($_.Exception.Message)" }
	}
	else {
		$results.Add((Invoke-Pester -Configuration (& $newPesterConfiguration ([string[]]$assigned) $true)))
	}

	$containers = @($results | ForEach-Object { $_.Containers })
	$summary.counts.total = [int](($results | Measure-Object -Property TotalCount -Sum).Sum)
	$summary.counts.passed = [int](($results | Measure-Object -Property PassedCount -Sum).Sum)
	$summary.counts.failed = [int](($results | Measure-Object -Property FailedCount -Sum).Sum)
	$summary.counts.skipped = [int](($results | Measure-Object -Property SkippedCount -Sum).Sum)
	$summary.counts.notRun = [int](($results | Measure-Object -Property NotRunCount -Sum).Sum)

	$summary.containers = @(
		foreach ($container in $containers) {
			[ordered]@{
				path       = [string]$container.Item
				durationMs = [int]$container.Duration.TotalMilliseconds
				total      = [int]$container.TotalCount
				passed     = [int]$container.PassedCount
				failed     = [int]$container.FailedCount
				skipped    = [int]$container.SkippedCount
			}
		}
	)

	$summary.failures = @(
		foreach ($failure in @($results | ForEach-Object { $_.Failed })) {
			$message = if ($failure.ErrorRecord) { [string]$failure.ErrorRecord[0].Exception.Message } else { '' }
			if ($message.Length -gt 2048) { $message = $message.Substring(0, 2048) + ' ...(truncated)' }
			[ordered]@{
				test    = [string]$failure.ExpandedPath
				file    = [string]$failure.ScriptBlock.File
				line    = [int]$failure.StartLine
				message = $message
			}
		}
	)

	& $writeSummary

	if ($summary.counts.failed -gt 0) { exit 1 }

	# A bucket that ran fewer containers than it was handed means a file was never executed -
	# a discovery-time parse error, say. That is an infrastructure failure, not a pass.
	if ($containers.Count -ne $assigned.Count) {
		Write-Host "Worker ${WorkerId}: ran $($containers.Count) of $($assigned.Count) assigned files."
		exit 2
	}
	if (@($results | Where-Object { $_.Result -eq 'Failed' }).Count -gt 0) {
		Write-Host "Worker ${WorkerId}: Pester reported Failed with no failed tests."
		exit 2
	}

	exit 0
}

# | ------------------------------ < Orchestrator Role > ------------------------------ | #

$runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# The orchestrator's helpers are plain scripts beside this one, for the same reason this is a
# script: CI runs it with zero WinuX modules loaded.
foreach ($helper in @(
		'Get-ExpectedTestCount', 'Get-MedianTestDuration', 'Get-TestFileWeight',
		'Get-AdaptiveWorkerCount', 'Read-WorkerHistory', 'Write-WorkerHistory', 'Test-WorkerSampleRecordable',
		'Start-RunConditionSampler', 'Stop-RunConditionSampler', 'Get-RunConditionSummary',
		'Get-ChangedPaths', 'Get-TestReferenceMap', 'Get-TestImpact', 'Read-ImpactMap', 'Get-WorkingTreeFingerprint', 'Get-SelectorMisses')) {
	. (Join-Path -Path $PSScriptRoot -ChildPath "$helper.ps1")
}

# Everything the harness remembers between runs lives in Results\ (gitignored) and is optional:
# a missing or corrupt file only means "nothing known yet".
$script:WorkerHistoryFile = Join-Path -Path $script:ResultsRoot -ChildPath 'workers.json'
$script:DependencyMapFile = Join-Path -Path $script:ResultsRoot -ChildPath 'dependency-map.json'
$script:ImpactMapFile = Join-Path -Path $script:ResultsRoot -ChildPath 'impact-map.json'
$script:LastSelectionFile = Join-Path -Path $script:ResultsRoot -ChildPath 'last-selection.json'
$script:LastGreenFile = Join-Path -Path $script:ResultsRoot -ChildPath 'last-green.json'
$script:RequiredPester = $null
try { $script:RequiredPester = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'RequiredPesterVersion.txt') -ErrorAction Stop | Select-Object -First 1).Trim() } catch { }

# -BuildImpactMap and -Changed/-Quick describe different runs: a map can only be built from the
# full suite, and a selection is pointless when every file runs anyway.
if ($BuildImpactMap -and ($CI -or $TestName -or $Path -or $Changed -or $Quick)) {
	Write-Host -ForegroundColor Red "`n=> -BuildImpactMap records what the FULL suite executes; it cannot be combined with -CI, -TestName, -Path, -Changed or -Quick."
	exit 2
}

# -Quick leaves out the Integration tier (real git, real processes, real waits). CI ignores it:
# the gate always runs everything.
$excludeTags = @(if ($Quick -and -not $CI) { 'Integration' })

# The -f operator formats with the current culture, which would render durations as "3,90s" and
# millisecond counts as "1.059ms" on a comma-decimal machine. The run log has to read identically
# everywhere (and gets pasted into issues), so every formatted number goes through invariant.
$invariant = [System.Globalization.CultureInfo]::InvariantCulture

$interactive = $false
if (-not $CI) {
	try { $interactive = -not [Console]::IsOutputRedirected } catch { $interactive = $false }
}

# --- Discovery: same semantics Run-Tests has always had ---

if ($Path) {
	if (-not (Test-Path -Path $Path)) {
		Write-Host -ForegroundColor Red "`n=> Test path not found: $Path"
		exit 2
	}
	$searchRoots = @((Resolve-Path -Path $Path).Path)
}
else {
	# Default discovery also sweeps the fork-owned Custom area (Modules\Custom\<Module>\Tests),
	# so fork-local functions meet the same "tests required" bar before graduating upstream.
	$searchRoots = @($PSScriptRoot)
	if (Test-Path -LiteralPath $script:CustomRoot) {
		$searchRoots += $script:CustomRoot
	}
}

# One -Filter per pattern rather than a single -Include: -Filter is applied by the file system
# provider, -Include only after every file under the roots has been enumerated. The union is
# deduplicated, so a file two patterns both match is still run once.
$patterns = @($TestName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$filters = if ($patterns.Count -gt 0) { @($patterns | ForEach-Object { "*$_*.Tests.ps1" }) } else { @('*.Tests.ps1') }
$testFiles = @(
	foreach ($filter in $filters) {
		Get-ChildItem -Path $searchRoots -Recurse -Filter $filter -File -ErrorAction SilentlyContinue |
			Select-Object -ExpandProperty FullName
	}
) | Sort-Object -Unique
$testFiles = @($testFiles)

# --- -Changed: run only what the changes since the base can affect ---

# The selection is conservative (Get-TestImpact): a test it cannot prove unaffected runs, and a
# changed path it does not recognize runs everything. In CI, -Since only AUDITS the selection - the
# full suite always runs there, and a failing file outside what -Changed would have picked is
# reported as a selector miss.
$changedRun = [bool]($Changed -and -not $CI)
$auditRun = [bool]($CI -and $Since)
$selection = $null
$selectionBase = $null
$forcedFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($changedRun -or $auditRun) {
	$defaultRoots = @($PSScriptRoot)
	if (Test-Path -LiteralPath $script:CustomRoot) { $defaultRoots += $script:CustomRoot }
	$allTestFiles = @(Get-ChildItem -Path $defaultRoots -Recurse -Filter '*.Tests.ps1' -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName | Sort-Object -Unique)

	$changes = Get-ChangedPaths -RepositoryRoot $script:PowerShellRoot -Since $Since
	if ($changes.Error) {
		$selection = [pscustomobject]@{ FullSuite = $true; FullSuiteReasons = @("git could not list the changes ($($changes.Error))"); Files = [ordered]@{}; Notes = @() }
	}
	else {
		$selectionBase = $changes
		$impactMap = Read-ImpactMap -Path $script:ImpactMapFile -RepositoryRoot $changes.Root -PesterVersion $script:RequiredPester
		$selection = Get-TestImpact -ChangedPaths $changes.Paths -AddedPaths $changes.Added -DeletedPaths $changes.Deleted `
			-RepositoryRoot $changes.Root -PowerShellRoot $script:PowerShellRoot -TestFiles $allTestFiles `
			-CachePath $script:DependencyMapFile -ImpactMap $impactMap.Map
		if ($impactMap.Note) { $selection.Notes = @($selection.Notes) + $impactMap.Note }
	}

	if ($changedRun) {
		$union = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
		if ($patterns.Count -gt 0 -or $Path) { foreach ($file in $testFiles) { [void]$union.Add($file) } }
		$picked = if ($selection.FullSuite) { $allTestFiles } else { @($selection.Files.Keys) }
		foreach ($file in $picked) { [void]$union.Add($file) }
		$testFiles = @($union)

		# A file selected because its own subject changed runs whole, even under -Quick.
		foreach ($file in $selection.Files.Keys) {
			if (@($selection.Files[$file] | Where-Object { $_ -eq 'changed' -or $_ -like 'tests *' }).Count -gt 0) { [void]$forcedFiles.Add($file) }
		}

		$against = if ($selectionBase) { "$($selectionBase.BaseRef) (merge base $($selectionBase.Base.Substring(0, [Math]::Min(10, $selectionBase.Base.Length)))), $(@($selectionBase.Paths).Count) changed path(s)" } else { 'an unknown base' }
		Write-Host ''
		if ($selection.FullSuite) {
			Write-Host -ForegroundColor DarkCyan " -Changed against $against - running the FULL suite:"
			foreach ($reason in $selection.FullSuiteReasons) { Write-Host -ForegroundColor DarkGray "   $reason" }
		}
		else {
			Write-Host -ForegroundColor DarkCyan " -Changed against $against - $(@($selection.Files.Keys).Count) test file(s) selected:"
			$shown = 0
			foreach ($file in $selection.Files.Keys) {
				if ($shown -ge 40) { Write-Host -ForegroundColor DarkGray "   ... and $(@($selection.Files.Keys).Count - 40) more - the run log lists every file and why."; break }
				$reasons = @($selection.Files[$file])
				$shownReasons = ($reasons | Select-Object -First 3) -join '; '
				if ($reasons.Count -gt 3) { $shownReasons += "; +$($reasons.Count - 3) more" }
				Write-Host -ForegroundColor DarkGray ("   {0}  <- {1}" -f (Split-Path -Path $file -Leaf), $shownReasons)
				$shown++
			}
		}
		foreach ($note in @($selection.Notes)) { Write-Host -ForegroundColor DarkGray "   note: $note" }

		if ($testFiles.Count -eq 0) {
			Write-Host -ForegroundColor Yellow "`n No test file is affected by the changes - nothing to run."
			exit 0
		}
	}
}

if ($testFiles.Count -eq 0) {
	$scope = if ($patterns.Count -gt 0) { "matching pattern(s): $($patterns -join ', ')" } else { "in: $($searchRoots -join ', ')" }
	if ($CI) {
		Write-Host -ForegroundColor Red "`n=> No test files found $scope - refusing to report a green run."
		exit 2
	}
	Write-Host -ForegroundColor Yellow "`n No test files found $scope"
	exit 0
}

# --- Results directory ---

foreach ($directory in @($script:ResultsRoot, $script:WorkRoot)) {
	if (-not (Test-Path -LiteralPath $directory)) {
		New-Item -ItemType Directory -Path $directory -Force | Out-Null
	}
}

# Retention runs on this run's OWN artifacts and on completed older ones only - never on a
# wildcard that could catch a run still in flight. Keep the ten most recent run logs, the same
# shape Clear-OldLogs keeps session logs, and let each run's XMLs live and die with its log.
$retainedLogs = 10
$existingLogs = @(Get-ChildItem -Path $script:ResultsRoot -Filter 'TestRun_*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
if ($existingLogs.Count -ge $retainedLogs) {
	foreach ($stale in ($existingLogs | Select-Object -Skip ($retainedLogs - 1))) {
		try { Remove-Item -LiteralPath $stale.FullName -Force -ErrorAction Stop } catch { }
	}
}

# An XML whose run log is gone is an orphan. Anything belonging to a live run keeps its log,
# because the log is written before this point on the next run and never deleted while retained.
$liveRunIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[void]$liveRunIds.Add($script:RunId)
foreach ($log in (Get-ChildItem -Path $script:ResultsRoot -Filter 'TestRun_*.log' -File -ErrorAction SilentlyContinue)) {
	[void]$liveRunIds.Add(($log.BaseName -replace '^TestRun_', ''))
}
foreach ($xml in (Get-ChildItem -Path $script:ResultsRoot -Filter 'pester-results-*.xml' -File -ErrorAction SilentlyContinue)) {
	$owner = ($xml.BaseName -replace '^pester-results-', '') -replace '-worker\d+$', ''
	if (-not $liveRunIds.Contains($owner)) {
		try { Remove-Item -LiteralPath $xml.FullName -Force -ErrorAction Stop } catch { }
	}
}

# Work directories are removed by the run that owns them; a killed run leaves one behind, so
# sweep anything over a day old rather than growing forever.
$workParent = Split-Path -Path $script:WorkRoot -Parent
foreach ($abandoned in (Get-ChildItem -Path $workParent -Directory -ErrorAction SilentlyContinue)) {
	if ($abandoned.FullName -ne $script:WorkRoot -and $abandoned.LastWriteTime -lt (Get-Date).AddDays(-1)) {
		try { Remove-Item -LiteralPath $abandoned.FullName -Recurse -Force -ErrorAction Stop } catch { }
	}
}

# --- Bucketing ---

# Weights come from the previous run's measured per-file durations (Results\timings.json, written
# at the end of every run). A file with no entry yet is seeded from its statically counted tests
# (Get-TestFileWeight); an Integration-tagged one gets a fixed heavy seed so a new real-git file
# is never stacked on other heavy files on its first run. On a cold checkout - CI, or a freshly
# cloned fork - nothing is cached and file size stands in.
$relativeKey = {
	param([string]$FullPath)
	$key = $FullPath
	if ($key.StartsWith($script:PowerShellRoot, [StringComparison]::OrdinalIgnoreCase)) {
		$key = $key.Substring($script:PowerShellRoot.Length).TrimStart('\', '/')
	}
	$key -replace '\\', '/'
}

$timings = @{}
if (Test-Path -LiteralPath $script:TimingsFile) {
	try {
		$cached = Get-Content -LiteralPath $script:TimingsFile -Raw | ConvertFrom-Json
		foreach ($property in $cached.PSObject.Properties) {
			$timings[$property.Name] = $property.Value
		}
	}
	catch { $timings = @{} }
}

# Tags decide two things before anything is spawned: -Quick drops a file whose every test is
# Integration-tagged, and an Integration file with no timing gets the heavy seed. Parsing every
# file costs a second or two, so only the files that mention the tag at all, and the files the
# median seed needs a count for, are parsed here; the full count for the live counter still
# happens while the workers bootstrap.
$medianMsPerTest = Get-MedianTestDuration -Timings $timings
$integrationPattern = [regex]::new('(?i)-Tags?\b[^\r\n{]*Integration')
$preCounted = @{}
$preCountTargets = @(
	foreach ($file in $testFiles) {
		$key = & $relativeKey $file
		$untimed = -not ($timings.ContainsKey($key) -and $timings[$key].ms)
		$mentionsTag = $false
		try { $mentionsTag = $integrationPattern.IsMatch([System.IO.File]::ReadAllText($file)) } catch { }
		if ($mentionsTag -or ($untimed -and $medianMsPerTest -gt 0)) { $file }
	}
)
if ($preCountTargets.Count -gt 0) {
	foreach ($row in @(Get-ExpectedTestCount -Path $preCountTargets -ExcludeTag $excludeTags)) { $preCounted[$row.Path] = $row }
}

# -Quick: a file whose tests are all excluded is not dispatched at all - no worker pays its
# discovery and BeforeAll for nothing. A file with only some excluded tests runs with Pester's
# ExcludeTag.
$quickSkipped = [System.Collections.Generic.List[string]]::new()
if ($excludeTags.Count -gt 0) {
	$testFiles = @(
		foreach ($file in $testFiles) {
			$row = $preCounted[$file]
			if ($row -and $row.Resolved -and $row.Count -eq 0 -and $row.Excluded -gt 0 -and -not $forcedFiles.Contains($file)) { $quickSkipped.Add($file) } else { $file }
		}
	)
	if ($testFiles.Count -eq 0) {
		Write-Host -ForegroundColor Yellow "`n Every selected test file is Integration-tagged and -Quick skips them all - nothing to run."
		try { Remove-Item -LiteralPath $script:WorkRoot -Recurse -Force -ErrorAction Stop } catch { }
		exit 0
	}
}

$weighted = foreach ($file in $testFiles) {
	$key = & $relativeKey $file
	$row = $preCounted[$file]
	$timing = if ($timings.ContainsKey($key)) { $timings[$key] } else { $null }
	$weight = Get-TestFileWeight -Timing $timing `
		-ExpectedCount $(if ($row) { $row.Count + $row.Excluded } else { 0 }) `
		-IsIntegration $([bool]($row -and @($row.Tags) -contains 'Integration')) `
		-FileBytes (Get-Item -LiteralPath $file).Length `
		-MedianMsPerTest $medianMsPerTest
	[pscustomobject]@{
		FullName   = $file
		Name       = Split-Path -Path $file -Leaf
		Weight     = $weight
		Serialized = $script:SerializedFiles -contains (Split-Path -Path $file -Leaf)
	}
}
$weighted = @($weighted)
$totalWeightMs = [double](($weighted | Measure-Object -Property Weight -Sum).Sum)

# --- Worker count ---

# An explicit -Workers always wins. CI keeps the static default and never reads or writes the
# history. Everything else asks the learner, which uses what earlier full runs measured on this
# machine (Results\workers.json); a scoped run also never gets more workers than its work can
# keep busy past their own start-up.
$scopedRun = [bool]($patterns.Count -gt 0 -or $Path -or $Quick -or $changedRun -or $BuildImpactMap)
$processorCount = [Environment]::ProcessorCount
$workerFingerprint = '{0}|{1}' -f $processorCount, ([int]([math]::Round($testFiles.Count / 50.0, [MidpointRounding]::AwayFromZero) * 50))
$workerChoice = $null
if ($Workers -gt 0) {
	$workerChoice = [pscustomobject]@{ Count = $Workers; Phase = 'Explicit'; Reason = 'explicit -Workers' }
}
elseif ($CI) {
	$workerChoice = [pscustomobject]@{ Count = [Math]::Min($processorCount, 12); Phase = 'CI'; Reason = 'CI default: min(CPU, 12)' }
}
else {
	$history = if ($scopedRun) {
		Read-WorkerHistory -Path $script:WorkerHistoryFile -ProcessorCount $processorCount
	}
	else {
		Read-WorkerHistory -Path $script:WorkerHistoryFile -Fingerprint $workerFingerprint
	}
	$workerChoice = Get-AdaptiveWorkerCount -Runs $history.Runs -Recorded $history.Recorded -ProcessorCount $processorCount `
		-FileCount $testFiles.Count -TotalWeightMs $totalWeightMs -Scoped:$scopedRun
}

$workerCount = [Math]::Max(1, [Math]::Min([int]$workerChoice.Count, $testFiles.Count))

$buckets = @(for ($i = 0; $i -lt $workerCount; $i++) { [pscustomobject]@{ Index = $i; Load = 0.0; Files = [System.Collections.Generic.List[string]]::new() } })

# Longest-processing-time first: the heaviest file lands first and every later file goes to
# whichever bucket is currently lightest. Cheap, and within a few percent of optimal here.
# The serialized files are seeded into bucket 0 up front so they can never land in two
# different workers and race on the machine state they touch.
foreach ($item in ($weighted | Where-Object { $_.Serialized } | Sort-Object Weight -Descending)) {
	$buckets[0].Files.Add($item.FullName)
	$buckets[0].Load += $item.Weight
}
foreach ($item in ($weighted | Where-Object { -not $_.Serialized } | Sort-Object Weight -Descending)) {
	$target = $buckets | Sort-Object Load | Select-Object -First 1
	$target.Files.Add($item.FullName)
	$target.Load += $item.Weight
}
$buckets = @($buckets | Where-Object { $_.Files.Count -gt 0 })

# --- Resolve the worker host ---

$pwshPath = $null
if ($PSVersionTable.PSEdition -eq 'Core') {
	$candidate = Join-Path -Path $PSHOME -ChildPath 'pwsh.exe'
	if (Test-Path -LiteralPath $candidate) { $pwshPath = $candidate }
}
if (-not $pwshPath) {
	$pwshPath = (Get-Command -Name 'pwsh' -ErrorAction SilentlyContinue | Select-Object -First 1).Source
}
if (-not $pwshPath) {
	Write-Host -ForegroundColor Red "`n=> PowerShell 7 (pwsh) was not found - the test workers cannot be started. Install it with Install-Applications or winget install Microsoft.PowerShell."
	exit 2
}

# --- Spawn ---

# The tags every worker excludes. Empty unless -Quick - and empty again when -Changed forced an
# Integration file in because its own subject changed: Pester's filter is per worker, not per file,
# so the forced file could otherwise lose its tests. Running a partially tagged file whole is the
# conservative side of that trade.
$workerExcludeTags = @($excludeTags)
if ($workerExcludeTags.Count -gt 0 -and @($testFiles | Where-Object { $forcedFiles.Contains($_) -and $preCounted[$_] -and $preCounted[$_].Excluded -gt 0 }).Count -gt 0) {
	$workerExcludeTags = @()
}

# Optional: a different temp root for the workers, so TestDrive (and the thousands of small files
# the real-git tests write) can live on a Dev Drive whose Defender performance mode defers
# scanning. Unset - the default - changes nothing. Creating that volume is the user's decision.
$testTempRoot = $null
if ($env:WINUX_TEST_TEMP) {
	try {
		if (-not (Test-Path -LiteralPath $env:WINUX_TEST_TEMP)) { New-Item -ItemType Directory -Path $env:WINUX_TEST_TEMP -Force -ErrorAction Stop | Out-Null }
		$testTempRoot = (Resolve-Path -LiteralPath $env:WINUX_TEST_TEMP -ErrorAction Stop).Path
	}
	catch {
		Write-Host -ForegroundColor Yellow "`n WINUX_TEST_TEMP [$env:WINUX_TEST_TEMP] is not usable ($($_.Exception.Message)) - workers use the default temp folder."
		$testTempRoot = $null
	}
}

# The tree under test, read before anything runs: the gate stamp of a green full run has to name
# what was tested, not whatever the tree became while the run was going.
$treeAtStart = $null
if (-not $CI -and (-not $scopedRun -or $changedRun -or $Quick -or $BuildImpactMap)) {
	$treeAtStart = Get-WorkingTreeFingerprint -RepositoryRoot $script:PowerShellRoot
}

# Run conditions (A1): what the machine was doing during the run, sampled in the background.
# Local runs only - a CI runner is a fresh VM whose load says nothing about this machine.
$sampler = $null
if (-not $CI) {
	try { $sampler = Start-RunConditionSampler -ExcludePids $PID } catch { $sampler = $null }
}

$workerStates = @(
	foreach ($bucket in $buckets) {
		@{
			Index      = $bucket.Index
			Files      = @($bucket.Files)
			ListPath   = Join-Path $script:WorkRoot ("worker{0}.files.txt" -f $bucket.Index)
			OutLog     = Join-Path $script:WorkRoot ("worker{0}.out.log" -f $bucket.Index)
			ErrLog     = Join-Path $script:WorkRoot ("worker{0}.err.log" -f $bucket.Index)
			XmlPath    = Join-Path $script:ResultsRoot ("pester-results-{0}-worker{1}.xml" -f $script:RunId, $bucket.Index)
			JsonPath   = Join-Path $script:WorkRoot ("worker{0}.summary.json" -f $bucket.Index)
			ImpactPath = Join-Path $script:WorkRoot ("worker{0}.impact.json" -f $bucket.Index)
			Process    = $null
			Reader     = $null
			TestCount  = 0
			Summary    = $null
			ExitCode   = $null
			SpawnedAt  = $null
			StartupSec = $null
		}
	}
)

# Reads whatever the worker has appended since the last poll and counts the finished tests in
# it. Pester's Detailed renderer writes exactly one "[+] name 12ms" line per completed test, so
# matching those lines gives a live count without the worker having to report progress at all.
# The StreamReader is kept open across polls so its UTF-8 decoder carries partial multi-byte
# sequences over a chunk boundary, and the file is opened shared - the worker still owns it.
$testLinePattern = [regex]::new('(?m)^\s*\[[+\-!?]\]\s')
$pumpTranscript = {
	param($State)
	try {
		if (-not $State.Reader) {
			if (-not (Test-Path -LiteralPath $State.OutLog)) { return }
			$stream = [System.IO.FileStream]::new(
				$State.OutLog,
				[System.IO.FileMode]::Open,
				[System.IO.FileAccess]::Read,
				([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
			$State.Reader = [System.IO.StreamReader]::new($stream, [System.Text.UTF8Encoding]::new($false), $false)
		}
		$chunk = $State.Reader.ReadToEnd()
		if ($chunk) { $State.TestCount += $testLinePattern.Matches($chunk).Count }
	}
	catch { }
}

$spinnerFrames = @('|', '/', '-', '\')
try {
	if ([Console]::OutputEncoding.CodePage -eq 65001) {
		$spinnerFrames = @([char]0x280B, [char]0x2819, [char]0x2839, [char]0x2838, [char]0x283C, [char]0x2834, [char]0x2826, [char]0x2827, [char]0x2807, [char]0x280F)
	}
}
catch { }

# The status line must never wrap. The wrap boundary is the BUFFER width, not the window width,
# and a braille frame can advance two terminal columns while counting as a single character - so
# the line is kept a few columns short of the boundary. A wrapped status line leaves a stray blank
# row behind, because the carriage return below only ever clears the last physical row, and that
# row is what showed up as an extra blank line above the verdict.
$statusWidth = {
	$width = 0
	try { $width = [int][Console]::BufferWidth } catch { }
	if ($width -lt 20) { try { $width = [int]$Host.UI.RawUI.WindowSize.Width } catch { } }
	if ($width -lt 20) { $width = 100 }
	$width - 3
}

$renderStatus = {
	param([string]$Text)
	if (-not $interactive) { return }
	$width = & $statusWidth
	$line = if ($Text.Length -gt $width) { $Text.Substring(0, $width) } else { $Text.PadRight($width) }
	Write-Host -NoNewline -ForegroundColor DarkCyan "`r$line"
}

# Leaves the cursor at the start of the blanked status row. The verdict then opens with a newline,
# so that row becomes the single blank line separating it from the title - the same spacing
# Write-LogTitle followed by Write-LogSuccess produces when no spinner was drawn at all.
$clearStatus = {
	if (-not $interactive) { return }
	Write-Host -NoNewline ("`r" + (' ' * (& $statusWidth)) + "`r")
}

if ($interactive) { try { [Console]::CursorVisible = $false } catch { } }

$aborted = $false
try {
	foreach ($state in $workerStates) {
		[System.IO.File]::WriteAllLines($state.ListPath, [string[]]$state.Files, [System.Text.UTF8Encoding]::new($false))

		$arguments = @(
			'-NoProfile'
			'-NonInteractive'
			'-ExecutionPolicy', 'Bypass'
			'-File', ('"{0}"' -f $PSCommandPath)
			'-Worker'
			'-WorkerId', $state.Index
			'-FileListPath', ('"{0}"' -f $state.ListPath)
			'-ResultXmlPath', ('"{0}"' -f $state.XmlPath)
			'-SummaryJsonPath', ('"{0}"' -f $state.JsonPath)
		)
		if ($workerExcludeTags.Count -gt 0) {
			$arguments += '-ExcludeTag'
			$arguments += ($workerExcludeTags -join ',')
		}
		if ($BuildImpactMap) {
			$arguments += '-ImpactMapPath'
			$arguments += ('"{0}"' -f $state.ImpactPath)
		}

		# The workers inherit this process's environment, so the temp root is swapped in only
		# around the spawn and put back straight after.
		$savedTemp = $env:TEMP
		$savedTmp = $env:TMP
		try {
			if ($testTempRoot) { $env:TEMP = $testTempRoot; $env:TMP = $testTempRoot }
			$state.SpawnedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
			$state.Process = Start-Process -FilePath $pwshPath -ArgumentList $arguments -PassThru -WindowStyle Hidden `
				-WorkingDirectory $script:PowerShellRoot `
				-RedirectStandardOutput $state.OutLog -RedirectStandardError $state.ErrLog
		}
		finally {
			$env:TEMP = $savedTemp
			$env:TMP = $savedTmp
		}
		if ($sampler -and $state.Process) { [void]$sampler.State.ExcludePids.TryAdd($state.Process.Id, 0) }
	}

	# The counter's denominator comes from the files about to run, not from the previous run.
	# Pester 6 discovers and runs each file interleaved, so no worker knows its own total before
	# it is done, and a discovery-only pass costs about a quarter of the whole suite; reading the
	# count off each file's syntax tree takes a second or two, spent here while the workers are
	# still bootstrapping. A file whose case list is computed at discovery time cannot be counted
	# that way and takes the previous run's count for that file instead.
	$expectedTests = 0
	foreach ($counted in @(Get-ExpectedTestCount -Path $testFiles -ExcludeTag $workerExcludeTags)) {
		$key = & $relativeKey $counted.Path
		if (-not $counted.Resolved -and $timings.ContainsKey($key) -and $timings[$key].tests) {
			$expectedTests += [int]$timings[$key].tests
		}
		else {
			$expectedTests += $counted.Count
		}
	}

	if ($CI) {
		Write-Host "Running $($testFiles.Count) test file(s) across $($workerStates.Count) worker(s)..."
	}

	Write-Host ""
	$frame = 0
	while ($true) {
		foreach ($state in $workerStates) { & $pumpTranscript $state }

		$finished = @($workerStates | Where-Object { $_.Process.HasExited }).Count
		$ran = ($workerStates | Measure-Object -Property TestCount -Sum).Sum
		$elapsed = $runStopwatch.Elapsed.TotalSeconds

		# A computed case list that grew since the cached run can push the count past the
		# denominator; never show more tests run than expected.
		if ($ran -gt $expectedTests) { $expectedTests = $ran }
		$counter = if ($expectedTests -gt 0) { "$ran/$expectedTests tests" } else { "$ran tests" }
		& $renderStatus ([string]::Format($invariant, '{0} Running {1} test file(s) on {2} worker(s)  |  {3}  |  {4}/{5} done  |  {6:N1}s',
				$spinnerFrames[$frame % $spinnerFrames.Count], $testFiles.Count, $workerStates.Count, $counter, $finished, $workerStates.Count, $elapsed))
		$frame++

		if ($finished -eq $workerStates.Count) { break }
		Start-Sleep -Milliseconds 100
	}

	# One last pump: the tail written between the final poll and process exit is not in the
	# counter yet, and the readers must be closed before the transcripts are merged.
	foreach ($state in $workerStates) { & $pumpTranscript $state }
}
finally {
	if ($interactive) { try { [Console]::CursorVisible = $true } catch { } }
	& $clearStatus

	foreach ($state in $workerStates) {
		if ($state.Reader) { try { $state.Reader.Dispose() } catch { } }
		if ($state.Process) {
			if (-not $state.Process.HasExited) {
				# Reached on Ctrl+C: kill the tree so no orphan worker keeps running tests
				# against the machine after the terminal has moved on.
				$aborted = $true
				try { $state.Process.Kill($true) } catch { }
				try { $null = $state.Process.WaitForExit(5000) } catch { }
			}
			# Read the exit code before disposing - it is unavailable afterwards - and dispose
			# it before the merge, because Start-Process keeps the two redirect files open in
			# THIS process until the Process object is released, which is what would otherwise
			# leave the Work directory undeletable.
			try { $state.ExitCode = $state.Process.ExitCode } catch { }
			try { $state.Process.Dispose() } catch { }
		}
	}

	$conditionSamples = @()
	if ($sampler) { try { $conditionSamples = @(Stop-RunConditionSampler -Sampler $sampler) } catch { $conditionSamples = @() } }
}

$runStopwatch.Stop()

# --- Aggregate ---

$infrastructureError = $aborted
$totals = @{ total = 0; passed = 0; failed = 0; skipped = 0; notRun = 0 }
$allContainers = [System.Collections.Generic.List[object]]::new()
$allFailures = [System.Collections.Generic.List[object]]::new()
$workerNotes = [System.Collections.Generic.List[string]]::new()
$pesterVersion = 'unknown'

foreach ($state in $workerStates) {
	if (Test-Path -LiteralPath $state.JsonPath) {
		try { $state.Summary = Get-Content -LiteralPath $state.JsonPath -Raw | ConvertFrom-Json }
		catch { $state.Summary = $null }
	}

	if (-not $state.Summary) {
		$infrastructureError = $true
		$tail = ''
		if (Test-Path -LiteralPath $state.ErrLog) {
			$tail = (Get-Content -LiteralPath $state.ErrLog -Tail 20 -ErrorAction SilentlyContinue) -join "`n"
		}
		$workerNotes.Add("Worker $($state.Index) produced no summary (exit code $($state.ExitCode), $($state.Files.Count) file(s) assigned).")
		if ($tail) { $workerNotes.Add("Worker $($state.Index) stderr tail:`n$tail") }
		continue
	}

	if ($state.Summary.bootstrapError) {
		$infrastructureError = $true
		$workerNotes.Add("Worker $($state.Index) failed to bootstrap: $($state.Summary.bootstrapError)")
		continue
	}

	if ($state.ExitCode -eq 2) {
		$infrastructureError = $true
		$workerNotes.Add("Worker $($state.Index) exited 2 (ran $(@($state.Summary.containers).Count) of $($state.Files.Count) assigned file(s)).")
	}

	if ($state.Summary.pesterVersion) { $pesterVersion = $state.Summary.pesterVersion }

	if ($state.Summary.testsStartedAt -and $state.SpawnedAt) {
		try { $state.StartupSec = [math]::Round(([double]$state.Summary.testsStartedAt - [double]$state.SpawnedAt) / 1000.0, 2) } catch { }
	}

	$totals.total += [int]$state.Summary.counts.total
	$totals.passed += [int]$state.Summary.counts.passed
	$totals.failed += [int]$state.Summary.counts.failed
	$totals.skipped += [int]$state.Summary.counts.skipped
	$totals.notRun += [int]$state.Summary.counts.notRun

	foreach ($container in @($state.Summary.containers)) {
		$allContainers.Add([pscustomobject]@{
				Worker     = $state.Index
				Path       = $container.path
				Name       = Split-Path -Path $container.path -Leaf
				DurationMs = [int]$container.durationMs
				Total      = [int]$container.total
				Passed     = [int]$container.passed
				Failed     = [int]$container.failed
				Skipped    = [int]$container.skipped
			})
	}
	foreach ($failure in @($state.Summary.failures)) {
		$allFailures.Add([pscustomobject]@{
				Worker  = $state.Index
				Test    = $failure.test
				File    = $failure.file
				Line    = [int]$failure.line
				Message = $failure.message
			})
	}
}

$serialMs = ($allContainers | Measure-Object -Property DurationMs -Sum).Sum
if (-not $serialMs) { $serialMs = 0 }

# --- Cache this run's measurements: the next run's bucketing, and the counter's fallback ---

try {
	foreach ($container in $allContainers) {
		# A file that ran with some of its tests excluded measured only part of itself; caching
		# that would make the next full run treat a heavy Integration file as a light one. An
		# impact-map build runs every file under breakpoints, about twice as slowly.
		if ($BuildImpactMap) { break }
		$row = $preCounted[[string]$container.Path]
		if ($workerExcludeTags.Count -gt 0 -and $row -and $row.Excluded -gt 0) { continue }
		$key = & $relativeKey $container.Path
		$timings[$key] = [pscustomobject]@{ ms = $container.DurationMs; tests = $container.Total }
	}
	$ordered = [ordered]@{}
	foreach ($key in ($timings.Keys | Sort-Object)) { $ordered[$key] = $timings[$key] }
	[System.IO.File]::WriteAllText($script:TimingsFile, ($ordered | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
}
catch { }

$wallSeconds = $runStopwatch.Elapsed.TotalSeconds
$runIsGreen = ($totals.failed -eq 0 -and -not $infrastructureError)
# A -Changed run that fell back to the full suite (and excluded nothing) proved as much as a plain
# full run, so it stamps the gate the same way. -BuildImpactMap runs the full suite too.
$provedWholeSuite = (-not $scopedRun) -or $BuildImpactMap -or ($changedRun -and $selection -and $selection.FullSuite -and -not $Quick -and $patterns.Count -eq 0 -and -not $Path)
$failedFiles = @($allContainers | Where-Object { $_.Failed -gt 0 } | ForEach-Object { & $relativeKey $_.Path } | Sort-Object -Unique)
$bookkeeping = [System.Collections.Generic.List[string]]::new()

# --- -BuildImpactMap: merge what every worker recorded into Results\impact-map.json ---

if ($BuildImpactMap) {
	try {
		$functionFileByName = @{}
		foreach ($moduleRoot in @($script:ModulesRoot, $script:CustomRoot)) {
			foreach ($moduleDirectory in @(Get-ChildItem -LiteralPath $moduleRoot -Directory -ErrorAction SilentlyContinue)) {
				$functionsDirectory = Join-Path $moduleDirectory.FullName 'Functions'
				if (-not (Test-Path -LiteralPath $functionsDirectory)) { continue }
				foreach ($file in @(Get-ChildItem -LiteralPath $functionsDirectory -Filter '*.ps1' -File)) { $functionFileByName[$file.BaseName] = & $relativeKey $file.FullName }
			}
		}
		$tests = [ordered]@{}
		$recordedFiles = 0
		foreach ($state in $workerStates) {
			if (-not (Test-Path -LiteralPath $state.ImpactPath)) { continue }
			$recorded = Get-Content -LiteralPath $state.ImpactPath -Raw | ConvertFrom-Json
			foreach ($property in $recorded.PSObject.Properties) {
				$tests[(& $relativeKey $property.Name)] = @(@($property.Value) | Where-Object { $functionFileByName.ContainsKey($_) } | ForEach-Object { $functionFileByName[$_] } | Sort-Object -Unique)
				$recordedFiles++
			}
		}
		if ($recordedFiles -ne $testFiles.Count) {
			$bookkeeping.Add("Impact map     : NOT written - recorded $recordedFiles of $($testFiles.Count) test files")
		}
		else {
			$head = @(git -C $script:PowerShellRoot rev-parse HEAD 2>$null)[0]
			$document = [ordered]@{ commit = "$head".Trim(); pester = $script:RequiredPester; built = (Get-Date).ToString('o'); tests = $tests }
			[System.IO.File]::WriteAllText($script:ImpactMapFile, ($document | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
			$bookkeeping.Add("Impact map     : written for $recordedFiles test files at $($document.commit) - Results\impact-map.json")
		}
	}
	catch {
		$bookkeeping.Add("Impact map     : NOT written - $($_.Exception.Message)")
	}
}

# --- Gate stamp: every green full run records the tree it proved ---

$lastGreen = $null
try { if (Test-Path -LiteralPath $script:LastGreenFile) { $lastGreen = Get-Content -LiteralPath $script:LastGreenFile -Raw | ConvertFrom-Json } } catch { $lastGreen = $null }
if ($provedWholeSuite -and -not $CI -and $runIsGreen -and $treeAtStart) {
	try {
		$stamp = [ordered]@{ head = $treeAtStart.Head; tree = $treeAtStart.Fingerprint; pester = $pesterVersion; at = (Get-Date).ToString('o') }
		[System.IO.File]::WriteAllText($script:LastGreenFile, ($stamp | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
		$lastGreen = [pscustomobject]$stamp
		$bookkeeping.Add("Gate stamp     : this tree is green on the full suite (Results\last-green.json)")
	}
	catch { }
}

# A selection or a quick run proves less than the gate does. Say so when the tree in front of you
# has no green full run yet - a reminder, never a block.
$gateReminder = $null
if (($changedRun -or $Quick) -and -not $CI -and -not $provedWholeSuite) {
	if (-not $treeAtStart -or -not $lastGreen -or $lastGreen.tree -ne $treeAtStart.Fingerprint) {
		$gateReminder = 'Selection only - this tree has no green full run yet; run the full suite (Run-Tests) before merging.'
	}
}

# --- Selector audit: did the selection miss a file that failed? ---

$selectorMisses = [System.Collections.Generic.List[string]]::new()
if ($changedRun -and $selection) {
	try {
		$record = [ordered]@{
			at        = (Get-Date).ToString('o')
			head      = $(if ($treeAtStart) { $treeAtStart.Head })
			tree      = $(if ($treeAtStart) { $treeAtStart.Fingerprint })
			base      = $(if ($selectionBase) { $selectionBase.Base })
			fullSuite = [bool]$selection.FullSuite
			files     = @($testFiles | ForEach-Object { & $relativeKey $_ })
		}
		[System.IO.File]::WriteAllText($script:LastSelectionFile, ($record | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
	}
	catch { }
}
elseif (-not $scopedRun -and -not $CI -and $failedFiles.Count -gt 0) {
	# A full run that fails in a file the last -Changed run did not select is a selector miss - the
	# rule that should have picked it needs fixing.
	try {
		if (Test-Path -LiteralPath $script:LastSelectionFile) {
			$lastSelection = Get-Content -LiteralPath $script:LastSelectionFile -Raw | ConvertFrom-Json
			foreach ($file in (Get-SelectorMisses -FailedFiles $failedFiles -SelectedFiles @($lastSelection.files) -FullSuite:([bool]$lastSelection.fullSuite))) {
				$selectorMisses.Add("$file failed, but the last -Changed run ($($lastSelection.at)) did not select it")
			}
		}
	}
	catch { }
}
elseif ($auditRun -and $selection) {
	if ($selection.FullSuite) {
		$reasons = @($selection.FullSuiteReasons)
		$shownReasons = ($reasons | Select-Object -First 3) -join '; '
		if ($reasons.Count -gt 3) { $shownReasons += "; and $($reasons.Count - 3) more" }
		$bookkeeping.Add("Selector       : -Changed would have run the full suite ($shownReasons)")
	}
	else {
		$picked = @($selection.Files.Keys | ForEach-Object { & $relativeKey $_ })
		foreach ($file in (Get-SelectorMisses -FailedFiles $failedFiles -SelectedFiles $picked)) {
			$selectorMisses.Add("$file failed, but -Changed since $Since would not have selected it")
		}
		$bookkeeping.Add("Selector       : -Changed since $Since would have run $($picked.Count) of $($allTestFiles.Count) files; $($failedFiles.Count) file(s) failed, $($selectorMisses.Count) outside the selection")
	}
}

# --- Run conditions, and what this run teaches the worker-count learner ---

$conditions = Get-RunConditionSummary -Samples $conditionSamples -ProcessorCount $processorCount `
	-StartupSeconds @($workerStates | ForEach-Object { $_.StartupSec } | Where-Object { $null -ne $_ })
$recordable = Test-WorkerSampleRecordable -CI:$CI -ExplicitWorkers:($Workers -gt 0) -Scoped:$scopedRun `
	-FailedCount $totals.failed -InfrastructureError:$infrastructureError -ForeignLoadPercent $conditions.ForeignLoadPercent
$historyNote = "not recorded: $($recordable.Reason)"
if ($recordable.Recordable) {
	$historySample = [ordered]@{
		workers        = $workerStates.Count
		wallSec        = [math]::Round($wallSeconds, 2)
		at             = (Get-Date).ToString('o')
		phase          = [string]$workerChoice.Phase
		foreignLoad    = $conditions.ForeignLoadPercent
		avgCpu         = $conditions.AvgCpuPercent
		minPerformance = $conditions.MinPerformancePercent
		startupAvg     = $conditions.StartupAvg
	}
	$historyNote = if (Write-WorkerHistory -Path $script:WorkerHistoryFile -Fingerprint $workerFingerprint -Sample $historySample) {
		[string]::Format($invariant, 'recorded ({0} workers, {1:N1}s) for machine {2}', $workerStates.Count, $wallSeconds, $workerFingerprint)
	}
	else { 'not recorded: the history file could not be written' }
}

# --- Run log ---

# Named for the run, not for "now": the XMLs already carry $RunId, and pairing them by name is
# what lets retention tell an orphaned XML from a live one.
$runLogPath = Join-Path -Path $script:ResultsRoot -ChildPath "TestRun_$($script:RunId).log"

$machineLine = if ($conditions.SampleCount -gt 0) {
	$parts = [System.Collections.Generic.List[string]]::new()
	if ($null -ne $conditions.AvgCpuPercent) { $parts.Add([string]::Format($invariant, 'CPU avg {0:N0}% (max {1:N0}%)', $conditions.AvgCpuPercent, $conditions.MaxCpuPercent)) }
	if ($null -ne $conditions.MinPerformancePercent) { $parts.Add([string]::Format($invariant, 'clock min {0:N0}% of rated', $conditions.MinPerformancePercent)) }
	if ($null -ne $conditions.MinAvailableMB) { $parts.Add([string]::Format($invariant, 'memory min {0:N0} MB free', $conditions.MinAvailableMB)) }
	$parts.Add([string]::Format($invariant, 'foreign load {0:N1}%', $conditions.ForeignLoadPercent))
	$top = @($conditions.TopConsumers | ForEach-Object { [string]::Format($invariant, '{0} {1:N1}s', $_.Name, $_.CpuSeconds) })
	if ($top.Count -gt 0) { $parts.Add("top other CPU: $($top -join ', ')") }
	($parts -join ', ') + [string]::Format($invariant, ' ({0} samples)', $conditions.SampleCount)
}
elseif ($CI) { 'not sampled (CI)' }
else { 'not sampled (the run was too short, or the sampler could not read the machine)' }

$startupLine = if ($null -ne $conditions.StartupAvg) {
	[string]::Format($invariant, 'min {0:N1}s, avg {1:N1}s, max {2:N1}s per worker (spawn to first test file)', $conditions.StartupMin, $conditions.StartupAvg, $conditions.StartupMax)
}
else { 'unknown' }

$modeParts = [System.Collections.Generic.List[string]]::new()
if ($excludeTags.Count -gt 0) {
	$modeParts.Add("Quick: tests tagged $($excludeTags -join ', ') excluded, $($quickSkipped.Count) wholly tagged file(s) not dispatched")
}
if ($testTempRoot) { $modeParts.Add("worker temp root $testTempRoot (WINUX_TEST_TEMP)") }

$summaryLines = [System.Collections.Generic.List[string]]::new()
$summaryLines.Add("Pester run - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$summaryLines.Add("Repository     : $script:PowerShellRoot")
$summaryLines.Add("Pester         : $pesterVersion")
$summaryLines.Add("Test files     : $($testFiles.Count)$(if ($patterns.Count -gt 0) { " (filter: $(($patterns | ForEach-Object { "*$_*" }) -join ', '))" })")
if ($modeParts.Count -gt 0) { $summaryLines.Add("Mode           : $($modeParts -join '; ')") }
$summaryLines.Add("Workers        : $($workerStates.Count) - $($workerChoice.Phase): $($workerChoice.Reason)")
$summaryLines.Add("Wall clock     : $([math]::Round($wallSeconds, 2))s")
$summaryLines.Add("Serial time    : $([math]::Round($serialMs / 1000.0, 2))s across all containers")
$summaryLines.Add("Tests          : $($totals.total) total, $($totals.passed) passed, $($totals.failed) failed, $($totals.skipped) skipped, $($totals.notRun) not run")
$summaryLines.Add("Machine        : $machineLine")
$summaryLines.Add("Start-up       : $startupLine")
$summaryLines.Add("Worker history : $historyNote")
foreach ($line in $bookkeeping) { $summaryLines.Add($line) }
if ($gateReminder) { $summaryLines.Add("Gate           : $gateReminder") }
$summaryLines.Add('')

if ($selectorMisses.Count -gt 0) {
	$summaryLines.Add("Selector misses ($($selectorMisses.Count)) - a rule in Get-TestImpact should have selected these")
	foreach ($miss in $selectorMisses) { $summaryLines.Add("  ! $miss") }
	$summaryLines.Add('')
}

if ($changedRun -and $selection) {
	if ($selection.FullSuite) {
		$summaryLines.Add('Selection - the full suite, because:')
		foreach ($reason in $selection.FullSuiteReasons) { $summaryLines.Add("  $reason") }
	}
	else {
		$summaryLines.Add("Selection - $(@($selection.Files.Keys).Count) file(s) against $(if ($selectionBase) { "$($selectionBase.BaseRef) ($($selectionBase.Base))" } else { 'an unknown base' })")
		foreach ($file in $selection.Files.Keys) { $summaryLines.Add("  $(& $relativeKey $file)  <- $(@($selection.Files[$file]) -join '; ')") }
	}
	foreach ($note in @($selection.Notes)) { $summaryLines.Add("  note: $note") }
	$summaryLines.Add('')
}

$summaryLines.Add('Workers')
foreach ($state in $workerStates) {
	if ($state.Summary -and -not $state.Summary.bootstrapError) {
		$startup = if ($null -ne $state.StartupSec) { [string]::Format($invariant, '{0,5:N1}s', $state.StartupSec) } else { '    ?' }
		$summaryLines.Add([string]::Format($invariant, '  [{0}] {1,4} file(s)  {2,5} test(s)  {3,7:N2}s  start-up {4}  exit {5}',
				$state.Index, $state.Files.Count, [int]$state.Summary.counts.total, [double]$state.Summary.durationSec, $startup, $state.ExitCode))
	}
	else {
		$summaryLines.Add([string]::Format($invariant, '  [{0}] {1,4} file(s)  ----- FAILED TO REPORT -----  exit {2}',
				$state.Index, $state.Files.Count, $state.ExitCode))
	}
}
$summaryLines.Add('')

foreach ($note in $workerNotes) {
	$summaryLines.Add("!! $note")
}
if ($workerNotes.Count -gt 0) { $summaryLines.Add('') }

if ($allFailures.Count -gt 0) {
	$summaryLines.Add("Failures ($($allFailures.Count))")
	foreach ($failure in $allFailures) {
		$summaryLines.Add("  x $($failure.Test)")
		$summaryLines.Add("      $($failure.File):$($failure.Line)")
		foreach ($messageLine in ($failure.Message -split "`r?`n")) {
			$summaryLines.Add("      $messageLine")
		}
		$summaryLines.Add('')
	}
}

$summaryLines.Add('Slowest 20 files')
foreach ($container in ($allContainers | Sort-Object DurationMs -Descending | Select-Object -First 20)) {
	$summaryLines.Add([string]::Format($invariant, '  {0,8}ms  {1,4} test(s)  w{2}  {3}',
			$container.DurationMs, $container.Total, $container.Worker, $container.Name))
}
$summaryLines.Add('')

$logLines = [System.Collections.Generic.List[string]]::new()
$logLines.AddRange($summaryLines)
$logLines.Add('=' * 100)
$logLines.Add('Worker transcripts - everything the run wrote to the console, per worker.')
$logLines.Add('=' * 100)
foreach ($state in $workerStates) {
	$logLines.Add('')
	$logLines.Add('-' * 100)
	$logLines.Add("Worker $($state.Index) - $($state.Files.Count) file(s), exit $($state.ExitCode)")
	$logLines.Add('-' * 100)
	foreach ($logFile in @($state.OutLog, $state.ErrLog)) {
		if (-not (Test-Path -LiteralPath $logFile)) { continue }
		$content = @(Get-Content -LiteralPath $logFile -ErrorAction SilentlyContinue)
		if ($content.Count -eq 0) { continue }
		if ($logFile -eq $state.ErrLog) {
			$logLines.Add('')
			$logLines.Add("--- worker $($state.Index) stderr ---")
		}
		$logLines.AddRange([string[]]$content)
	}
}

try {
	[System.IO.File]::WriteAllLines($runLogPath, [string[]]$logLines, [System.Text.UTF8Encoding]::new($false))
}
catch {
	Write-Host -ForegroundColor Red "`n=> Failed to write the run log: $($_.Exception.Message)"
}

try { Remove-Item -LiteralPath $script:WorkRoot -Recurse -Force -ErrorAction Stop } catch { }

# --- Console verdict ---

if ($CI -or $Detailed) {
	foreach ($line in $summaryLines) { Write-Host $line }
}
if ($Detailed) {
	foreach ($line in $logLines[$summaryLines.Count..($logLines.Count - 1)]) { Write-Host $line }
}

if (-not ($CI -or $Detailed) -and $allFailures.Count -gt 0) {
	Write-Host ''
	foreach ($failure in ($allFailures | Select-Object -First 20)) {
		Write-Host -ForegroundColor Red "  x $($failure.Test)"
		Write-Host -ForegroundColor DarkGray "      $($failure.File):$($failure.Line)"
		Write-Host -ForegroundColor DarkGray "      $(($failure.Message -split "`r?`n")[0])"
	}
	if ($allFailures.Count -gt 20) {
		Write-Host -ForegroundColor DarkGray "  ... and $($allFailures.Count - 20) more - see the run log."
	}
}

foreach ($note in $workerNotes) {
	Write-Host -ForegroundColor Red "`n=> $note"
}

$exitCode = 0
if ($totals.failed -gt 0) { $exitCode = 1 }
if ($infrastructureError) { $exitCode = 2 }

$workerLabel = if ($workerStates.Count -eq 1) { '1 worker' } else { "$($workerStates.Count) workers" }
if ($exitCode -eq 0) {
	Write-Host -ForegroundColor Green "`n=> All tests passed! ($($totals.passed) passed in $([math]::Round($wallSeconds, 1))s across $workerLabel)"
}
elseif ($exitCode -eq 1) {
	Write-Host -ForegroundColor Red "`n=> Tests failed: $($totals.failed) failed, $($totals.passed) passed"
}
else {
	Write-Host -ForegroundColor Red "`n=> Test run did not complete cleanly - see the run log."
}
Write-Host ''
Write-Host -ForegroundColor DarkGray "  Log file location => $runLogPath"

if ($selectorMisses.Count -gt 0) {
	Write-Host ''
	Write-Host -ForegroundColor Yellow "  Selector miss: $($selectorMisses.Count) failing file(s) that -Changed did not (or would not) select - see the run log."
	if ($CI) {
		# GitHub Actions annotations, so a miss shows on the PR next to the file it concerns.
		$repositoryPrefix = "$(@(git -C $script:PowerShellRoot rev-parse --show-prefix 2>$null)[0])".Trim()
		foreach ($miss in $selectorMisses) {
			$file = ($miss -split ' ', 2)[0]
			Write-Host "::warning file=$repositoryPrefix$file::Selector miss: $miss"
		}
	}
}
if ($gateReminder) {
	Write-Host -ForegroundColor DarkYellow "  $gateReminder"
}

if ($PassThru) {
	[pscustomobject]@{
		Result         = if ($exitCode -eq 0) { 'Passed' } else { 'Failed' }
		TotalCount     = $totals.total
		PassedCount    = $totals.passed
		FailedCount    = $totals.failed
		SkippedCount   = $totals.skipped
		NotRunCount    = $totals.notRun
		Duration       = $runStopwatch.Elapsed
		Workers        = $workerStates.Count
		WorkerChoice   = $workerChoice
		Conditions     = $conditions
		Selection      = $selection
		SelectorMisses = @($selectorMisses)
		Containers     = @($allContainers)
		Failures       = @($allFailures)
		ResultFiles    = @($workerStates | ForEach-Object { $_.XmlPath } | Where-Object { Test-Path -LiteralPath $_ })
		RunLog         = $runLogPath
		ExitCode       = $exitCode
	}
}

exit $exitCode
