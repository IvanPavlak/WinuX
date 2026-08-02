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

        The terminal shows only a spinner with a live test counter and the final verdict.
        Everything a detailed serial run would have printed goes to
        Modules/Tests/Results/TestRun_<timestamp>.log (gitignored, like the Logging module's
        Logs folder), next to the per-worker NUnit XMLs.

    .PARAMETER TestName
        Optional filter to run only tests matching a specific pattern (e.g., "Open-Terminal")

    .PARAMETER Path
        Optional path to test files. Defaults to the Tests directory.

    .PARAMETER Workers
        Number of parallel worker processes. Defaults to min(CPU count, 8, test file count).

    .PARAMETER Detailed
        Echo the whole run log, including every worker transcript, after the run

    .PARAMETER PassThru
        Return the aggregate result object

    .EXAMPLE
        Run-Tests
        Runs all tests in the Tests directory

    .EXAMPLE
        Run-Tests -TestName "Open-Terminal"
        Runs only tests matching "Open-Terminal"

    .EXAMPLE
        Run-Tests -Detailed
        Runs all tests and prints the full run log afterwards

    .EXAMPLE
        Run-Tests -Workers 1
        Runs everything in a single worker (useful when diagnosing cross-test interference)
    #>
	[CmdletBinding()]
	param(
		[Parameter(Position = 0)]
		[string]$TestName,

		[Parameter()]
		[string]$Path,

		[Parameter()]
		[int]$Workers = 0,

		[Parameter()]
		[switch]$Detailed,

		[Parameter()]
		[switch]$PassThru
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

	# The harness owns all run output (spinner, failures, verdict, log path) so that a local run
	# and a CI run report identically. It exits 0 pass / 1 test failures / 2 infrastructure
	# failure; invoked with & the exit code lands in $LASTEXITCODE and this session lives on.
	$Result = & $Harness @HarnessArguments

	if ($PassThru) {
		return $Result
	}
}
