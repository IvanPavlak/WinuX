#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. "$ModuleRoot\System\Functions\Resolve-FastfetchAutoFitSettings.ps1"

	if (-not (Get-Command Write-LogWarning -ErrorAction SilentlyContinue)) { function Write-LogWarning { param($Message) } }
	if (-not (Get-Command Write-LogDebug -ErrorAction SilentlyContinue)) { function Write-LogDebug { param($Message) } }
}

Describe "Resolve-FastfetchAutoFitSettings" {
	BeforeEach {
		Mock Write-LogWarning { }
		Mock Write-LogDebug { }
		$script:SavedConfiguration = $global:Configuration
	}

	AfterEach {
		$global:Configuration = $script:SavedConfiguration
	}

	Context "defaults" {
		It "returns the built-in defaults when the section is <Label>" -ForEach @(
			@{ Label = "null"; Settings = $null }
			@{ Label = "empty"; Settings = @{} }
		) {
			$result = Resolve-FastfetchAutoFitSettings -Settings $Settings

			$result.MaxShrinkSteps | Should -Be 10
			$result.ReflowTimeoutMilliseconds | Should -Be 10
			$result.PromptReserve | Should -Be 1
			Should -Invoke Write-LogWarning -Times 0 -Exactly
		}

		It "reads the section from `$global:Configuration.FastfetchAutoFit by default" {
			$global:Configuration = @{ FastfetchAutoFit = @{ MaxShrinkSteps = 3; ReflowTimeoutMilliseconds = 500; PromptReserve = 2 } }

			$result = Resolve-FastfetchAutoFitSettings

			$result.MaxShrinkSteps | Should -Be 3
			$result.ReflowTimeoutMilliseconds | Should -Be 500
			$result.PromptReserve | Should -Be 2
		}

		It "falls back to the defaults when `$global:Configuration has no such section" {
			$global:Configuration = @{}

			$result = Resolve-FastfetchAutoFitSettings

			$result.MaxShrinkSteps | Should -Be 10
			$result.ReflowTimeoutMilliseconds | Should -Be 10
			$result.PromptReserve | Should -Be 1
		}

		It "returns every key as an [int]" {
			$result = Resolve-FastfetchAutoFitSettings -Settings @{ MaxShrinkSteps = "4" }

			$result.MaxShrinkSteps | Should -BeOfType [int]
			$result.MaxShrinkSteps | Should -Be 4
			$result.ReflowTimeoutMilliseconds | Should -BeOfType [int]
			$result.PromptReserve | Should -BeOfType [int]
		}
	}

	Context "configuration layer" {
		It "takes a configured key and leaves the others at their defaults" {
			$result = Resolve-FastfetchAutoFitSettings -Settings @{ MaxShrinkSteps = 2 }

			$result.MaxShrinkSteps | Should -Be 2
			$result.ReflowTimeoutMilliseconds | Should -Be 10
			$result.PromptReserve | Should -Be 1
		}

		It "treats a `$null key as 'use the default' without warning" {
			$result = Resolve-FastfetchAutoFitSettings -Settings @{ MaxShrinkSteps = $null; PromptReserve = 3 }

			$result.MaxShrinkSteps | Should -Be 10
			$result.PromptReserve | Should -Be 3
			Should -Invoke Write-LogWarning -Times 0 -Exactly
		}

		It "accepts the range boundaries of <Key>" -ForEach @(
			@{ Key = "MaxShrinkSteps"; Low = 0; High = 50 }
			@{ Key = "PromptReserve"; Low = 0; High = 20 }
		) {
			(Resolve-FastfetchAutoFitSettings -Settings @{ $Key = $Low }).$Key | Should -Be $Low
			(Resolve-FastfetchAutoFitSettings -Settings @{ $Key = $High }).$Key | Should -Be $High
			Should -Invoke Write-LogWarning -Times 0 -Exactly
		}

		It "puts no upper bound on ReflowTimeoutMilliseconds - it is the per-machine tuning knob" {
			(Resolve-FastfetchAutoFitSettings -Settings @{ ReflowTimeoutMilliseconds = 1 }).ReflowTimeoutMilliseconds | Should -Be 1
			(Resolve-FastfetchAutoFitSettings -Settings @{ ReflowTimeoutMilliseconds = 60000 }).ReflowTimeoutMilliseconds | Should -Be 60000
			Should -Invoke Write-LogWarning -Times 0 -Exactly
		}

		It "warns once and uses the default when <Key> is <Label>" -ForEach @(
			@{ Key = "MaxShrinkSteps"; Label = "below the range"; Value = -1; Default = 10; Shape = "an integer between 0 and 50" }
			@{ Key = "MaxShrinkSteps"; Label = "above the range"; Value = 51; Default = 10; Shape = "an integer between 0 and 50" }
			@{ Key = "MaxShrinkSteps"; Label = "not a number"; Value = "many"; Default = 10; Shape = "an integer between 0 and 50" }
			@{ Key = "ReflowTimeoutMilliseconds"; Label = "zero"; Value = 0; Default = 10; Shape = "a positive integer" }
			@{ Key = "ReflowTimeoutMilliseconds"; Label = "negative"; Value = -5; Default = 10; Shape = "a positive integer" }
			@{ Key = "ReflowTimeoutMilliseconds"; Label = "a decimal"; Value = 1.5; Default = 10; Shape = "a positive integer" }
			@{ Key = "PromptReserve"; Label = "above the range"; Value = 21; Default = 1; Shape = "an integer between 0 and 20" }
			@{ Key = "PromptReserve"; Label = "a hashtable"; Value = @{ Rows = 1 }; Default = 1; Shape = "an integer between 0 and 20" }
		) {
			$result = Resolve-FastfetchAutoFitSettings -Settings @{ $Key = $Value }

			$result.$Key | Should -Be $Default
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "Configuration.FastfetchAutoFit.$Key must be $Shape - got*" }
		}

		It "warns for each invalid key separately and keeps the valid ones" {
			$result = Resolve-FastfetchAutoFitSettings -Settings @{ MaxShrinkSteps = "x"; ReflowTimeoutMilliseconds = 400; PromptReserve = 99 }

			$result.MaxShrinkSteps | Should -Be 10
			$result.ReflowTimeoutMilliseconds | Should -Be 400
			$result.PromptReserve | Should -Be 1
			Should -Invoke Write-LogWarning -Times 2 -Exactly
		}
	}

	Context "parameter layer" {
		It "lets an explicit parameter beat the configured value" {
			$result = Resolve-FastfetchAutoFitSettings -Settings @{ MaxShrinkSteps = 3 } -MaxShrinkSteps 1

			$result.MaxShrinkSteps | Should -Be 1
		}

		It "lets an explicit parameter beat the default when nothing is configured" {
			$result = Resolve-FastfetchAutoFitSettings -Settings $null -ReflowTimeoutMilliseconds 900 -PromptReserve 0

			$result.ReflowTimeoutMilliseconds | Should -Be 900
			$result.PromptReserve | Should -Be 0
			$result.MaxShrinkSteps | Should -Be 10
		}

		It "accepts 0 as an explicit MaxShrinkSteps (reset only, never shrink)" {
			(Resolve-FastfetchAutoFitSettings -Settings @{ MaxShrinkSteps = 10 } -MaxShrinkSteps 0).MaxShrinkSteps | Should -Be 0
		}

		It "warns and keeps the configured value when an explicit parameter is out of range" {
			$result = Resolve-FastfetchAutoFitSettings -Settings @{ MaxShrinkSteps = 3 } -MaxShrinkSteps 99

			$result.MaxShrinkSteps | Should -Be 3
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "-MaxShrinkSteps must be an integer between 0 and 50*" }
		}

		It "warns and keeps the default when an explicit parameter is out of range and nothing is configured" {
			$result = Resolve-FastfetchAutoFitSettings -Settings $null -ReflowTimeoutMilliseconds 0

			$result.ReflowTimeoutMilliseconds | Should -Be 10
			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like "-ReflowTimeoutMilliseconds must be a positive integer*" }
		}
	}
}
