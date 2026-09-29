#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Helper\Functions\Test-StartupStage.ps1")
}

Describe "Test-StartupStage" {
	BeforeEach {
		$global:WinuXStartupStage = $null
	}

	AfterAll {
		$global:WinuXStartupStage = $null
	}

	It "runs the stage and starts its clock when nothing is skipped" {
		Test-StartupStage -Name "Greeting" -Skip "" | Should -BeTrue

		$global:WinuXStartupStage.Name | Should -Be "Greeting"
		$global:WinuXStartupStage.Clock.IsRunning | Should -BeTrue
	}

	It "skips a stage named in the list and leaves no clock behind" {
		Test-StartupStage -Name "Terminal-Icons" -Skip "Greeting,Terminal-Icons" | Should -BeFalse

		$global:WinuXStartupStage | Should -BeNullOrEmpty
	}

	It "accepts semicolons and surrounding whitespace in the list" {
		Test-StartupStage -Name "PowerPlan" -Skip " Greeting ; PowerPlan " | Should -BeFalse
	}

	It "matches stage names without regard to case" {
		Test-StartupStage -Name "OhMyPosh" -Skip "ohmyposh" | Should -BeFalse
	}

	It "skips every stage when the list says All" {
		Test-StartupStage -Name "Aliases" -Skip "All" | Should -BeFalse
	}

	It "does not skip a stage whose name is only a prefix of a listed one" {
		Test-StartupStage -Name "PSReadLine" -Skip "PSReadLineOptions" | Should -BeTrue
	}

	It "runs a Required stage whatever the list says, and still times it" {
		Test-StartupStage -Name "Core" -Required -Skip "All,Core" | Should -BeTrue

		$global:WinuXStartupStage.Name | Should -Be "Core"
		$global:WinuXStartupStage.Clock.IsRunning | Should -BeTrue
	}

	It "reads the skip list from the environment by default" {
		$previous = $env:WINUX_STARTUP_SKIP
		try {
			$env:WINUX_STARTUP_SKIP = "Schema"
			Test-StartupStage -Name "Schema" | Should -BeFalse
			Test-StartupStage -Name "Greeting" | Should -BeTrue
		}
		finally {
			$env:WINUX_STARTUP_SKIP = $previous
		}
	}
}
