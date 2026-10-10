function Run-Tests {
	<#
    .SYNOPSIS
        Runs all Pester tests in the Tests directory

    .DESCRIPTION
        Discovers and runs all .Tests.ps1 files in the PowerShell Modules Tests directory.
        Default discovery also sweeps the fork-owned Custom area (Modules/Custom/<Module>/Tests)
        when present. Supports filtering by test name pattern and various output options.

        The run itself is performed by Invoke-TestSuite.ps1, which spreads the test files over
        parallel child pwsh processes. Each worker bootstraps its own session, so the tests can
        no longer pollute this one and no profile reload is needed afterwards.

        The terminal shows only a spinner with a live test counter and the final verdict. The
        counter's total is counted from the test files before the run starts, so it is right
        for the files about to run rather than carried over from the previous run.
        Everything a detailed serial run would have printed goes to
        Modules/Tests/Results/TestRun_<timestamp>.log (gitignored, like the Logging module's
        Logs folder), next to the per-worker NUnit XMLs.

    .PARAMETER TestName
        Optional filter to run only tests whose file name matches a pattern (e.g., "Open-Terminal").
        Several patterns run the union of their matches, each file once.

    .PARAMETER Path
        Optional path to test files. Defaults to the Tests directory.

    .PARAMETER Workers
        Number of parallel worker processes. Omitted, the harness picks the count itself: it learns
        the fastest count for this machine from earlier green full runs (Results/workers.json), and a
        scoped run never gets more workers than its files can keep busy. An explicit value always wins.

    .PARAMETER Detailed
        Echo the whole run log, including every worker transcript, after the run

    .PARAMETER PassThru
        Return the aggregate result object

    .PARAMETER Quick
        Skip the Integration tier - tests tagged Integration (real git, real processes). A file whose
        tests are all tagged is not run at all. Never the gate: run the full suite before merging.

    .PARAMETER Changed
        Run only the test files the changes since -Since (default: the merge base with master, plus
        uncommitted and untracked files) can affect, conservatively: when the selector cannot prove a
        test unaffected it runs it, and a change it does not recognize runs everything. The selection
        and the reason for each file are printed first. Combines with -TestName and -Path as a union.

    .PARAMETER Since
        The ref -Changed compares against. Defaults to master.

    .PARAMETER BuildImpactMap
        Run the full suite while recording which functions each test file actually invokes, into
        Results/impact-map.json; -Changed then also selects by what ran, not only by what the code
        says. Takes about twice as long as a normal run.

    .EXAMPLE
        Run-Tests
        Runs all tests in the Tests directory

    .EXAMPLE
        Run-Tests -TestName "Open-Terminal"
        Runs only tests matching "Open-Terminal"

    .EXAMPLE
        Run-Tests -TestName "Open-Terminal", "Close-Workspace"
        Runs every test file matching either pattern

    .EXAMPLE
        Run-Tests -Detailed
        Runs all tests and prints the full run log afterwards

    .EXAMPLE
        Run-Tests -Workers 1
        Runs everything in a single worker (useful when diagnosing cross-test interference)

    .EXAMPLE
        Run-Tests -Changed
        Runs only the test files the branch's changes can affect, and says why each one was picked

    .EXAMPLE
        Run-Tests -Changed -Quick
        The fastest everyday loop: the affected files, without the Integration tier unless the change is its subject

    .EXAMPLE
        Run-Tests -BuildImpactMap
        Full run that also refreshes the runtime impact map -Changed uses as its backstop
    #>
	[CmdletBinding()]
	param(
		[Parameter(Position = 0)]
		[string[]]$TestName,

		[Parameter()]
		[string]$Path,

		[Parameter()]
		[int]$Workers = 0,

		[Parameter()]
		[switch]$Detailed,

		[Parameter()]
		[switch]$PassThru,

		[Parameter()]
		[switch]$Quick,

		[Parameter()]
		[switch]$Changed,

		[Parameter()]
		[string]$Since,

		[Parameter()]
		[switch]$BuildImpactMap
	)

	$Harness = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "Invoke-TestSuite.ps1"
	if (-not (Test-Path -LiteralPath $Harness)) {
		Write-LogError "Test harness not found: $Harness"
		return
	}

	Write-LogTitle "Running Pester Tests"

	# Splatted rather than passed positionally so an unset filter stays unset - the harness
	# treats an empty -TestName as "no filter", but being explicit keeps the two in step.
	$HarnessArguments = @{}
	if ($TestName) { $HarnessArguments.TestName = $TestName }
	if ($Path) { $HarnessArguments.Path = $Path }
	if ($Workers -gt 0) { $HarnessArguments.Workers = $Workers }
	if ($Detailed) { $HarnessArguments.Detailed = $true }
	if ($PassThru) { $HarnessArguments.PassThru = $true }
	if ($Quick) { $HarnessArguments.Quick = $true }
	if ($Changed) { $HarnessArguments.Changed = $true }
	if ($Since) { $HarnessArguments.Since = $Since }
	if ($BuildImpactMap) { $HarnessArguments.BuildImpactMap = $true }

	# The harness owns all run output (spinner, failures, verdict, log path) so that a local run
	# and a CI run report identically. It exits 0 pass / 1 test failures / 2 infrastructure
	# failure; invoked with & the exit code lands in $LASTEXITCODE and this session lives on.
	$Result = & $Harness @HarnessArguments

	if ($PassThru) {
		return $Result
	}
}
