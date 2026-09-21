#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Helper\Functions\Register-DeferredAction.ps1")
	. (Join-Path $ModuleRoot "Helper\Functions\Complete-DeferredActions.ps1")
}

Describe "Complete-DeferredActions" {
	BeforeEach {
		$script:DeferredActions = $null
		Mock Write-LogDebug { }
		Mock Write-LogWarning { }
	}

	It "is a no-op that returns 0 when nothing is queued" {
		Complete-DeferredActions | Should -Be 0

		Should -Invoke Write-LogWarning -Times 0
	}

	It "returns how many tails ran" {
		Register-DeferredAction -Label 'one' -Action { }
		Register-DeferredAction -Label 'two' -Action { }

		Complete-DeferredActions | Should -Be 2
	}

	It "empties the queue, so a second drain in the same flow runs nothing" {
		$script:runs = 0
		Register-DeferredAction -Label 'once' -Action { $script:runs++ }

		Complete-DeferredActions | Should -Be 1
		Complete-DeferredActions | Should -Be 0
		$script:runs | Should -Be 1
	}

	It "reports a throwing tail under its label and still runs the tails behind it" {
		$script:order = @()
		Register-DeferredAction -Label 'fine' -Action { $script:order += 'fine' }
		Register-DeferredAction -Label 'broken' -Action { throw 'boom' }
		Register-DeferredAction -Label 'after' -Action { $script:order += 'after' }

		Complete-DeferredActions | Should -Be 3

		$script:order | Should -Be @('fine', 'after')
		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*[[]broken[]]*boom*' }
	}

	It "clears the queue before running, so a throwing tail cannot strand itself for the next flow" {
		Register-DeferredAction -Label 'broken' -Action { throw 'boom' }

		$null = Complete-DeferredActions
		Complete-DeferredActions | Should -Be 0
	}

	It "does not run a tail registered while draining until the next drain" {
		# The list being walked is a snapshot; a tail that queues another tail queues it for the
		# next flow, never for the current walk.
		$script:order = @()
		Register-DeferredAction -Label 'outer' -Action {
			$script:order += 'outer'
			Register-DeferredAction -Label 'inner' -Action { $script:order += 'inner' }
		}

		Complete-DeferredActions | Should -Be 1
		$script:order | Should -Be @('outer')
		Complete-DeferredActions | Should -Be 1
		$script:order | Should -Be @('outer', 'inner')
	}

	It "discards what the tail returns" {
		Register-DeferredAction -Label 'chatty' -Action { 'noise'; 42; $true }

		$result = Complete-DeferredActions
		$result | Should -Be 1
	}
}
