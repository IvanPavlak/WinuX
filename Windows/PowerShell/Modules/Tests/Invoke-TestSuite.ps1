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
	verdict and the path to the run log. Everything a serial `Invoke-Pester -Verbosity Detailed`
	would have printed - every per-test line and everything the code under test writes to the
	console - is captured per worker and merged into Results\TestRun_<stamp>_<PID>.log, alongside
	the per-worker NUnit XMLs. Every artifact is named after the run that produced it, so two
	concurrent runs cannot overwrite or misreport each other. Results\ is gitignored, exactly
	like the Logging module's Logs\.

	This script is intentionally NOT in Functions\ - Tests.psm1 dot-sources and exports every
	file there, and this is a script, not an exported function. It also deliberately uses plain
	Write-Host rather than Write-Log*: CI runs it before any WinuX module exists in the session.

.PARAMETER TestName
	Filter to files matching *<TestName>*.Tests.ps1. Omit to run everything discovered.

.PARAMETER Path
	Root to discover tests under. Defaults to this module's own directory, and additionally
	sweeps the fork-owned Custom area (Modules\Custom\<Module>\Tests) when no -Path is given.

.PARAMETER Workers
	Number of parallel worker processes. 0 (default) picks min(CPU count, 8, file count).

.PARAMETER Detailed
	Echo the whole run log - including every worker transcript - to the console after the run.

.PARAMETER CI
	Non-interactive mode: no spinner, plain progress lines, the run summary echoed to stdout,
	and "no test files found" treated as an infrastructure failure rather than a warning.

.PARAMETER PassThru
	Emit the aggregate result object.

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

.EXAMPLE
	.\Invoke-TestSuite.ps1
	Runs the whole suite on the default worker count.

.EXAMPLE
	.\Invoke-TestSuite.ps1 -TestName Open-Terminal -Workers 2
	Runs only *Open-Terminal*.Tests.ps1 on two workers.

.EXAMPLE
	.\Invoke-TestSuite.ps1 -CI
	The CI entry point: no spinner, summary on stdout, infrastructure failures exit 2.

.NOTES
	Exit codes: 0 = all tests passed, 1 = test failures, 2 = infrastructure failure (bootstrap
	failed, Pester missing, a worker died without writing its summary, a bucket ran fewer
	containers than it was assigned, or -CI matched no test files). A silently unrun file must
	never be able to green the gate.
#>

[CmdletBinding(DefaultParameterSetName = 'Orchestrate')]
param(
	[Parameter(ParameterSetName = 'Orchestrate', Position = 0)]
	[string]$TestName,

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

	[Parameter(ParameterSetName = 'Worker', Mandatory = $true)]
	[switch]$Worker,

	[Parameter(ParameterSetName = 'Worker', Mandatory = $true)]
	[string]$FileListPath,

	[Parameter(ParameterSetName = 'Worker', Mandatory = $true)]
	[string]$ResultXmlPath,

	[Parameter(ParameterSetName = 'Worker', Mandatory = $true)]
	[string]$SummaryJsonPath,

	[Parameter(ParameterSetName = 'Worker')]
	[int]$WorkerId = 0
)

$ProgressPreference = 'SilentlyContinue'

# The modules a worker session needs before any test runs. Tests Mock cross-module commands
# (Write-LogTitle, Resolve-Selection, Start-Application, ...), and Pester can only mock a
# command it can resolve - so these must be importable first or the mocks fail with
# "Could not find Command". This list is the whole session contract.
$script:BootstrapModules = @('Logging', 'Helper', 'System', 'Application', 'Git', 'Window', 'Workflow', 'Configuration', 'Bootstrap')

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

	# NOTE: this must never be named $Configuration - it would shadow the $global:Configuration
	# that the functions under test read through the unqualified name, and tests would fail in
	# ways that point nowhere near here.
	$pesterConfiguration = New-PesterConfiguration
	$pesterConfiguration.Run.Path = [string[]]$assigned
	$pesterConfiguration.Run.PassThru = $true
	# Detailed on purpose: this stream is redirected to the worker's transcript, never to the
	# terminal, and its one line per finished test is what the orchestrator counts to drive the
	# live counter.
	$pesterConfiguration.Output.Verbosity = 'Detailed'
	$pesterConfiguration.Output.RenderMode = 'Plaintext'
	$pesterConfiguration.TestResult.Enabled = $true
	$pesterConfiguration.TestResult.OutputFormat = 'NUnit3'
	$pesterConfiguration.TestResult.OutputPath = $ResultXmlPath

	$result = Invoke-Pester -Configuration $pesterConfiguration

	$summary.counts.total = [int]$result.TotalCount
	$summary.counts.passed = [int]$result.PassedCount
	$summary.counts.failed = [int]$result.FailedCount
	$summary.counts.skipped = [int]$result.SkippedCount
	$summary.counts.notRun = [int]$result.NotRunCount

	$summary.containers = @(
		foreach ($container in $result.Containers) {
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
		foreach ($failure in $result.Failed) {
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
	if ($result.Containers.Count -ne $assigned.Count) {
		Write-Host "Worker ${WorkerId}: ran $($result.Containers.Count) of $($assigned.Count) assigned files."
		exit 2
	}
	if ($result.Result -eq 'Failed') {
		Write-Host "Worker ${WorkerId}: Pester reported Failed with no failed tests."
		exit 2
	}

	exit 0
}

# | ------------------------------ < Orchestrator Role > ------------------------------ | #

$runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

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

$filter = if ($TestName) { "*$TestName*.Tests.ps1" } else { '*.Tests.ps1' }
$testFiles = @(
	Get-ChildItem -Path $searchRoots -Recurse -Filter $filter -File -ErrorAction SilentlyContinue |
		Select-Object -ExpandProperty FullName |
		Sort-Object -Unique
)

if ($testFiles.Count -eq 0) {
	$scope = if ($TestName) { "matching pattern: $TestName" } else { "in: $($searchRoots -join ', ')" }
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
# at the end of every run). On a cold checkout - CI, or a freshly cloned fork - nothing is cached
# yet and file size stands in: the suite averages roughly 15 bytes of test source per millisecond,
# plus a fixed per-file discovery cost.
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

$weighted = foreach ($file in $testFiles) {
	$key = & $relativeKey $file
	$weight = $null
	if ($timings.ContainsKey($key) -and $timings[$key].ms) {
		$weight = [double]$timings[$key].ms
	}
	if (-not $weight) {
		$weight = 150.0 + ((Get-Item -LiteralPath $file).Length / 15.0)
	}
	[pscustomobject]@{
		FullName   = $file
		Name       = Split-Path -Path $file -Leaf
		Weight     = $weight
		Serialized = $script:SerializedFiles -contains (Split-Path -Path $file -Leaf)
	}
}
$weighted = @($weighted)

$workerCount = $Workers
if ($workerCount -le 0) {
	$workerCount = [Math]::Min([Environment]::ProcessorCount, 8)
}
$workerCount = [Math]::Max(1, [Math]::Min($workerCount, $testFiles.Count))

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

$expectedTests = 0
foreach ($file in $testFiles) {
	$key = & $relativeKey $file
	if ($timings.ContainsKey($key) -and $timings[$key].tests) { $expectedTests += [int]$timings[$key].tests }
}

$workerStates = @(
	foreach ($bucket in $buckets) {
		@{
			Index     = $bucket.Index
			Files     = @($bucket.Files)
			ListPath  = Join-Path $script:WorkRoot ("worker{0}.files.txt" -f $bucket.Index)
			OutLog    = Join-Path $script:WorkRoot ("worker{0}.out.log" -f $bucket.Index)
			ErrLog    = Join-Path $script:WorkRoot ("worker{0}.err.log" -f $bucket.Index)
			XmlPath   = Join-Path $script:ResultsRoot ("pester-results-{0}-worker{1}.xml" -f $script:RunId, $bucket.Index)
			JsonPath  = Join-Path $script:WorkRoot ("worker{0}.summary.json" -f $bucket.Index)
			Process   = $null
			Reader    = $null
			TestCount = 0
			Summary   = $null
			ExitCode  = $null
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

		$state.Process = Start-Process -FilePath $pwshPath -ArgumentList $arguments -PassThru -WindowStyle Hidden `
			-WorkingDirectory $script:PowerShellRoot `
			-RedirectStandardOutput $state.OutLog -RedirectStandardError $state.ErrLog
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

# --- Cache this run's measurements for the next run's bucketing ---

try {
	foreach ($container in $allContainers) {
		$key = & $relativeKey $container.Path
		$timings[$key] = [pscustomobject]@{ ms = $container.DurationMs; tests = $container.Total }
	}
	$ordered = [ordered]@{}
	foreach ($key in ($timings.Keys | Sort-Object)) { $ordered[$key] = $timings[$key] }
	[System.IO.File]::WriteAllText($script:TimingsFile, ($ordered | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
}
catch { }

# --- Run log ---

# Named for the run, not for "now": the XMLs already carry $RunId, and pairing them by name is
# what lets retention tell an orphaned XML from a live one.
$runLogPath = Join-Path -Path $script:ResultsRoot -ChildPath "TestRun_$($script:RunId).log"
$wallSeconds = $runStopwatch.Elapsed.TotalSeconds

$summaryLines = [System.Collections.Generic.List[string]]::new()
$summaryLines.Add("Pester run - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$summaryLines.Add("Repository     : $script:PowerShellRoot")
$summaryLines.Add("Pester         : $pesterVersion")
$summaryLines.Add("Test files     : $($testFiles.Count)$(if ($TestName) { " (filter: *$TestName*)" })")
$summaryLines.Add("Workers        : $($workerStates.Count)")
$summaryLines.Add("Wall clock     : $([math]::Round($wallSeconds, 2))s")
$summaryLines.Add("Serial time    : $([math]::Round($serialMs / 1000.0, 2))s across all containers")
$summaryLines.Add("Tests          : $($totals.total) total, $($totals.passed) passed, $($totals.failed) failed, $($totals.skipped) skipped, $($totals.notRun) not run")
$summaryLines.Add('')

$summaryLines.Add('Workers')
foreach ($state in $workerStates) {
	if ($state.Summary -and -not $state.Summary.bootstrapError) {
		$summaryLines.Add([string]::Format($invariant, '  [{0}] {1,4} file(s)  {2,5} test(s)  {3,7:N2}s  exit {4}',
				$state.Index, $state.Files.Count, [int]$state.Summary.counts.total, [double]$state.Summary.durationSec, $state.ExitCode))
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

if ($PassThru) {
	[pscustomobject]@{
		Result       = if ($exitCode -eq 0) { 'Passed' } else { 'Failed' }
		TotalCount   = $totals.total
		PassedCount  = $totals.passed
		FailedCount  = $totals.failed
		SkippedCount = $totals.skipped
		NotRunCount  = $totals.notRun
		Duration     = $runStopwatch.Elapsed
		Workers      = $workerStates.Count
		Containers   = @($allContainers)
		Failures     = @($allFailures)
		ResultFiles  = @($workerStates | ForEach-Object { $_.XmlPath } | Where-Object { Test-Path -LiteralPath $_ })
		RunLog       = $runLogPath
		ExitCode     = $exitCode
	}
}

exit $exitCode
