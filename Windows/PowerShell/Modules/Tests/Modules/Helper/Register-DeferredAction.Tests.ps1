#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Helper\Functions\Register-DeferredAction.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\Complete-DeferredActions.ps1")
}

Describe "Register-DeferredAction" {
	BeforeEach {
		# Module state: what one test queues must never run in the next.
		$script:DeferredActions = $null
		Mock Write-LogDebug { }
		Mock Write-LogWarning { }
	}

	It "queues the tail so the drain runs it" {
		$script:ran = $false
		Register-DeferredAction -Label 'a tail' -Action { $script:ran = $true }

		$script:ran | Should -BeFalse
		Complete-DeferredActions | Should -Be 1
		$script:ran | Should -BeTrue
	}

	It "keeps the tails in registration order" {
		$script:order = @()
		Register-DeferredAction -Label 'first' -Action { $script:order += 'first' }
		Register-DeferredAction -Label 'second' -Action { $script:order += 'second' }
		Register-DeferredAction -Label 'third' -Action { $script:order += 'third' }

		Complete-DeferredActions | Should -Be 3
		$script:order | Should -Be @('first', 'second', 'third')
	}

	It "splats the parameters into the tail by name" {
		$script:seen = $null
		Register-DeferredAction -Label 'with args' -Parameters @{ Name = 'Server'; ColdStart = $true } -Action {
			param([string]$Name, [bool]$ColdStart)
			$script:seen = "$Name/$ColdStart"
		}

		$null = Complete-DeferredActions
		$script:seen | Should -Be 'Server/True'
	}

	It "captures the parameters by value, so the caller's later changes do not reach the tail" {
		$script:seen = $null
		$args = @{ Name = 'Before' }
		Register-DeferredAction -Label 'snapshot' -Parameters $args -Action { param([string]$Name) $script:seen = $Name }
		$args.Name = 'After'

		$null = Complete-DeferredActions
		$script:seen | Should -Be 'Before'
	}

	It "runs a tail that takes no parameters when none are given" {
		$script:ran = $false
		Register-DeferredAction -Label 'bare' -Action { $script:ran = $true }

		$null = Complete-DeferredActions
		$script:ran | Should -BeTrue
	}

	It "refuses an empty label, because the drain reports failures by it" {
		{ Register-DeferredAction -Label '' -Action { } } | Should -Throw
	}

	It "resolves functions from the session state the tail was written in" {
		# The registering module's own functions must be reachable when the flow, in another
		# module, runs the tail. Here the test scope stands in for the registering module.
		function Test-DeferredHelperVisible { 'visible' }
		$script:seen = $null
		Register-DeferredAction -Label 'closure' -Action { $script:seen = Test-DeferredHelperVisible }

		$null = Complete-DeferredActions
		$script:seen | Should -Be 'visible'
	}
}
