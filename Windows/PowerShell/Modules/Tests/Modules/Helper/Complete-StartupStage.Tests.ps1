#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Helper\Functions\Test-StartupStage.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\Complete-StartupStage.ps1")
}

Describe "Complete-StartupStage" {
	BeforeEach {
		$global:WinuXStartupStage = $null
		$global:WinuXStartupTimings = $null
		# $TestDrive persists across the tests of a Describe, so each test gets its own trace file.
		$script:trace = Join-Path $TestDrive ([guid]::NewGuid().ToString("N") + ".trace")
	}

	AfterAll {
		$global:WinuXStartupStage = $null
		$global:WinuXStartupTimings = $null
	}

	It "records the running stage's time and clears the stage" {
		$null = Test-StartupStage -Name "Greeting" -Skip ""
		Start-Sleep -Milliseconds 5

		Complete-StartupStage -TracePath ""

		$global:WinuXStartupTimings.Count | Should -Be 1
		$global:WinuXStartupTimings[0].Stage | Should -Be "Greeting"
		$global:WinuXStartupTimings[0].Milliseconds | Should -BeGreaterThan 0
		$global:WinuXStartupStage | Should -BeNullOrEmpty
	}

	It "keeps the stages in the order they completed" {
		foreach ($name in "Core", "Schema", "Greeting") {
			$null = Test-StartupStage -Name $name -Skip ""
			Complete-StartupStage -TracePath ""
		}

		@($global:WinuXStartupTimings | ForEach-Object Stage) | Should -Be @("Core", "Schema", "Greeting")
	}

	It "appends one tab-separated line per stage to the trace file, with an invariant decimal point" {
		foreach ($name in "Core", "OhMyPosh") {
			$null = Test-StartupStage -Name $name -Skip ""
			Complete-StartupStage -TracePath $script:trace
		}

		$lines = @([System.IO.File]::ReadAllLines($script:trace))
		$lines.Count | Should -Be 2
		$lines[0] | Should -Match "^Core`t\d+(\.\d)?$"
		$lines[1] | Should -Match "^OhMyPosh`t\d+(\.\d)?$"
	}

	It "does nothing when no stage clock is running" {
		Complete-StartupStage -TracePath $script:trace

		$global:WinuXStartupTimings | Should -BeNullOrEmpty
		Test-Path $script:trace | Should -BeFalse
	}

	It "survives a trace file that cannot be written" {
		$null = Test-StartupStage -Name "Aliases" -Skip ""

		{ Complete-StartupStage -TracePath (Join-Path $TestDrive "missing\folder\startup.trace") } | Should -Not -Throw
		$global:WinuXStartupTimings.Count | Should -Be 1
	}

	It "reads the trace path from the environment by default" {
		$previous = $env:WINUX_STARTUP_TRACE
		try {
			$env:WINUX_STARTUP_TRACE = $script:trace
			$null = Test-StartupStage -Name "PowerPlan" -Skip ""
			Complete-StartupStage

			(Get-Content $script:trace) | Should -Match "^PowerPlan`t"
		}
		finally {
			$env:WINUX_STARTUP_TRACE = $previous
		}
	}
}
