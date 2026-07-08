function Run-Tests {
	<#
    .SYNOPSIS
        Runs all Pester tests in the Tests directory

    .DESCRIPTION
        Discovers and runs all .Tests.ps1 files in the PowerShell Modules Tests directory.
        Supports filtering by test name pattern and various output options.

    .PARAMETER TestName
        Optional filter to run only tests matching a specific pattern (e.g., "Open-Terminal")

    .PARAMETER Path
        Optional path to test files. Defaults to the Tests directory.

    .PARAMETER Detailed
        Show detailed test results instead of summary

    .PARAMETER PassThru
        Return the Pester result object

    .EXAMPLE
        Run-Tests
        Runs all tests in the Tests directory

    .EXAMPLE
        Run-Tests -TestName "Open-Terminal"
        Runs only tests matching "Open-Terminal"

    .EXAMPLE
        Run-Tests -Detailed
        Runs all tests with detailed output
    #>
	[CmdletBinding()]
	param(
		[Parameter(Position = 0)]
		[string]$TestName,

		[Parameter()]
		[string]$Path,

		[Parameter()]
		[switch]$Detailed,

		[Parameter()]
		[switch]$PassThru
	)

	# Determine the tests root directory
	if (-not $Path) {
		$TestsRoot = Join-Path -Path $PSScriptRoot -ChildPath ".."
		$TestsRoot = Resolve-Path $TestsRoot
	}
	else {
		$TestsRoot = Resolve-Path $Path
	}

	Write-LogTitle "Running Pester Tests"

	# Find test files
	if ($TestName) {
		$TestFiles = Get-ChildItem -Path $TestsRoot -Recurse -Filter "*$TestName*.Tests.ps1"
		if ($TestFiles.Count -eq 0) {
			Write-LogWarning "No test files found matching pattern: $TestName"
			return
		}
		Write-LogStep "Running tests matching: $TestName"
	}
	else {
		$TestFiles = Get-ChildItem -Path $TestsRoot -Recurse -Filter "*.Tests.ps1"
		if ($TestFiles.Count -eq 0) {
			Write-LogWarning "No test files found in: $TestsRoot"
			return
		}
		Write-LogStep "Running all $($TestFiles.Count) test file(s)"
	}

	# Display test files to be run
	Write-LogStep "Test files:"
	$TestFiles | ForEach-Object {
		Write-LogStep "  - $($_.Name)" -NoLeadingNewline
	}
	Write-Host ""

	# Configure Pester
	$PesterConfig = @{
		Run    = @{
			Path = $TestFiles.FullName
		}
		Output = @{
			Verbosity = if ($Detailed) { 'Detailed' } else { 'Normal' }
		}
	}

	# Add PassThru if requested
	if ($PassThru) {
		$PesterConfig.Run.PassThru = $true
	}

	try {
		# Check Pester version
		$PesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1

		if (-not $PesterModule) {
			Write-LogError "Pester is not installed. Please run Install-PowerShellModules first."
			return
		}

		# Run tests based on Pester version
		if ($PesterModule.Version -ge [Version]"5.0.0") {
			# Pester 5.x - Use configuration object
			# NOTE: Variable MUST NOT be named $Configuration - it shadows the $global:Configuration
			# used by module functions under test (e.g., Send-WakeOnLan), causing test failures.
			$PesterConfiguration = New-PesterConfiguration -Hashtable $PesterConfig
			$Result = Invoke-Pester -Configuration $PesterConfiguration
		}
		else {
			# Pester 3.x/4.x - Use legacy parameters
			$InvokePesterParams = @{
				Path = $TestFiles.FullName
			}
			if ($PassThru) {
				$InvokePesterParams.PassThru = $true
			}
			$Result = Invoke-Pester @InvokePesterParams
		}

		Reload-PowerShellProfile

		# Display summary
		Write-Host ""
		if ($Result) {
			if ($Result.FailedCount -eq 0) {
				Write-LogSuccess "All tests passed! ($($Result.PassedCount) passed)"
			}
			else {
				Write-LogError "Tests failed: $($Result.FailedCount) failed, $($Result.PassedCount) passed"
			}
		}

		if ($PassThru) {
			return $Result
		}
	}
	catch {
		Write-LogError "Error running tests: $($_.Exception.Message)" -Exception $_
		throw
	}
}
