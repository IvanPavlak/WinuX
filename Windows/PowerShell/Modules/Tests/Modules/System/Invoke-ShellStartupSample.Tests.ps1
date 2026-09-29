#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "System\Functions\Invoke-ShellStartupSample.ps1")
	. (Join-Path $ModuleRoot "System\Functions\Read-ShellStartupTrace.ps1")

	# A stand-in for pwsh: a script that writes what the profile's stage guards would write into
	# the trace file the function hands it, so no real shell (and no real profile) is started.
	$script:fakeShell = Join-Path $TestDrive "fake-pwsh.cmd"
	Set-Content -Path $script:fakeShell -Encoding ascii -Value @(
		"@echo off"
		"echo Core	300.5>> ""%WINUX_STARTUP_TRACE%"""
		"echo Greeting	120>> ""%WINUX_STARTUP_TRACE%"""
		"echo %WINUX_STARTUP_SKIP%> ""%TEMP%\fake-pwsh-skip.txt"""
	)
	$script:skipRecord = Join-Path $env:TEMP "fake-pwsh-skip.txt"
}

Describe "Invoke-ShellStartupSample" {
	BeforeEach {
		Remove-Item -LiteralPath $script:skipRecord -Force -ErrorAction SilentlyContinue
		$script:previousSkip = $env:WINUX_STARTUP_SKIP
		$script:previousTrace = $env:WINUX_STARTUP_TRACE
		$env:WINUX_STARTUP_SKIP = "caller-value"
		$env:WINUX_STARTUP_TRACE = "caller-trace"
	}

	AfterEach {
		$env:WINUX_STARTUP_SKIP = $script:previousSkip
		$env:WINUX_STARTUP_TRACE = $script:previousTrace
		Remove-Item -LiteralPath $script:skipRecord -Force -ErrorAction SilentlyContinue
	}

	It "times the child and reads the per-stage trace it wrote" {
		$sample = Invoke-ShellStartupSample -Executable $script:fakeShell

		$sample.Milliseconds | Should -BeGreaterThan 0
		$sample.Stages["Core"] | Should -Be 300.5
		$sample.Stages["Greeting"] | Should -Be 120
	}

	It "hands the skip list to the child through WINUX_STARTUP_SKIP" {
		$null = Invoke-ShellStartupSample -Skip "Greeting,PowerPlan" -Executable $script:fakeShell

		(Get-Content $script:skipRecord).Trim() | Should -Be "Greeting,PowerPlan"
	}

	It "restores both environment variables afterwards" {
		$null = Invoke-ShellStartupSample -Skip "Schema" -Executable $script:fakeShell

		$env:WINUX_STARTUP_SKIP | Should -Be "caller-value"
		$env:WINUX_STARTUP_TRACE | Should -Be "caller-trace"
	}

	It "deletes the trace file it created" {
		$before = @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Filter "winux-startup-*.trace").Count
		$null = Invoke-ShellStartupSample -Executable $script:fakeShell
		$after = @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Filter "winux-startup-*.trace").Count

		$after | Should -Be $before
	}

	It "reports no stages for a bare start" {
		$sample = Invoke-ShellStartupSample -Bare -Executable $script:fakeShell

		$sample.Stages.Count | Should -Be 0
	}

	It "launches the running PowerShell by default" {
		$sample = Invoke-ShellStartupSample -Bare

		$sample.Milliseconds | Should -BeGreaterThan 0
	}
}
