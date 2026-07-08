#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Loading-Spinner.ps1"

	# Tears down any spinner the coordinator may still hold so a real
	# System.Timers.Timer / event subscription never leaks between tests.
	function Reset-SpinnerCoordinator {
		$c = $global:LoadingSpinnerCoordinator
		if ($c) {
			if ($c.Timer) { try { $c.Timer.Stop(); $c.Timer.Dispose() } catch {} }
			if ($c.EventSub) {
				Unregister-Event -SubscriptionId $c.EventSub.Id -ErrorAction SilentlyContinue
				Remove-Job -Id $c.EventSub.Id -Force -ErrorAction SilentlyContinue
			}
		}
		Get-EventSubscriber -ErrorAction SilentlyContinue |
			Where-Object { $_.SourceObject -is [System.Timers.Timer] } |
			Unregister-Event -ErrorAction SilentlyContinue
		$global:LoadingSpinnerCoordinator = $null
	}
}

Describe "Loading-Spinner" {
	BeforeEach {
		$global:Configuration = [PSCustomObject]@{}
		Mock Write-Host { }
	}

	It "returns when loading spinner configuration is missing" {
		{ Loading-Spinner -Function { "ok" } } | Should -Not -Throw
		Should -Invoke Write-Host -Times 1
	}
}

Describe "Loading-Spinner coordination (-Start / -Stop / -Pause / -Resume)" {
	BeforeEach {
		# A large delay keeps the background timer from firing during the test, so
		# only the deterministic synchronous renders run on the main thread.
		$global:Configuration = [PSCustomObject]@{
			LoadingSpinners = @{ Dots = @{ Symbols = @('|', '/', '-', '\'); Delay = 100000 } }
			DefaultSpinner  = 'Dots'
		}
		Reset-SpinnerCoordinator
		Mock Write-Host { }
	}

	AfterEach {
		Reset-SpinnerCoordinator
	}

	It "starts a single coordinator timer and tracks the spinner on the stack" {
		$h = Loading-Spinner -Start -Label "Outer"
		$c = $global:LoadingSpinnerCoordinator

		$c.Active | Should -BeTrue
		$c.Stack.Count | Should -Be 1
		$c.Timer | Should -Not -BeNullOrEmpty

		Loading-Spinner -Stop -Spinner $h
		$c.Active | Should -BeFalse
		$c.Stack.Count | Should -Be 0
		$c.Timer | Should -BeNullOrEmpty
	}

	It "does NOT create a second timer for a nested start - it relabels the single spinner" {
		$outer = Loading-Spinner -Start -Label "Outer"
		$firstTimer = $global:LoadingSpinnerCoordinator.Timer

		$inner = Loading-Spinner -Start -Label "Starting FancyZones..."
		$c = $global:LoadingSpinnerCoordinator

		$c.Stack.Count | Should -Be 2
		[object]::ReferenceEquals($c.Timer, $firstTimer) | Should -BeTrue
		$c.Stack[$c.Stack.Count - 1].Label | Should -Be "Starting FancyZones..."

		# Stopping the nested spinner reverts to the parent label, timer still alive.
		Loading-Spinner -Stop -Spinner $inner
		$c.Active | Should -BeTrue
		$c.Stack.Count | Should -Be 1
		$c.Stack[$c.Stack.Count - 1].Label | Should -Be "Outer"
		[object]::ReferenceEquals($c.Timer, $firstTimer) | Should -BeTrue

		# Stopping the outer (last) spinner tears the timer down.
		Loading-Spinner -Stop -Spinner $outer
		$c.Active | Should -BeFalse
		$c.Timer | Should -BeNullOrEmpty
	}

	It "Pause/Resume toggles the suspended flag without throwing" {
		$h = Loading-Spinner -Start -Label "Work"

		{ Loading-Spinner -Pause } | Should -Not -Throw
		$global:LoadingSpinnerCoordinator.Suspended | Should -BeTrue

		{ Loading-Spinner -Resume } | Should -Not -Throw
		$global:LoadingSpinnerCoordinator.Suspended | Should -BeFalse

		Loading-Spinner -Stop -Spinner $h
	}

	It "Stop is idempotent - a second stop of the same handle does not throw" {
		$h = Loading-Spinner -Start -Label "Work"
		Loading-Spinner -Stop -Spinner $h
		{ Loading-Spinner -Stop -Spinner $h } | Should -Not -Throw
		$global:LoadingSpinnerCoordinator.Active | Should -BeFalse
	}

	It "Pause / Resume / Stop are safe no-ops when no spinner is active" {
		{ Loading-Spinner -Pause } | Should -Not -Throw
		{ Loading-Spinner -Resume } | Should -Not -Throw
		{ Loading-Spinner -Stop -Spinner @{ Id = 'does-not-exist' } } | Should -Not -Throw
	}

	It "Stop with a null spinner handle is a safe no-op (does not stop the active spinner)" {
		$h = Loading-Spinner -Start -Label "Work"
		{ Loading-Spinner -Stop -Spinner $null } | Should -Not -Throw
		$global:LoadingSpinnerCoordinator.Active | Should -BeTrue
		Loading-Spinner -Stop -Spinner $h
		$global:LoadingSpinnerCoordinator.Active | Should -BeFalse
	}

	It "leaves a bare green checkmark when an empty-label spinner is stopped with -Completed" {
		$captured = New-Object System.Collections.Generic.List[string]
		Mock Write-Host { if ($null -ne $Object) { $captured.Add([string]$Object) } else { $captured.Add("") } }

		$h = Loading-Spinner -Start -Label ""
		Loading-Spinner -Stop -Spinner $h -Completed

		($captured -join "`n") | Should -Match '✓'
	}

	It "erases (no checkmark) when an empty-label spinner is stopped without -Completed" {
		$captured = New-Object System.Collections.Generic.List[string]
		Mock Write-Host { if ($null -ne $Object) { $captured.Add([string]$Object) } else { $captured.Add("") } }

		$h = Loading-Spinner -Start -Label ""
		Loading-Spinner -Stop -Spinner $h

		($captured -join "`n") | Should -Not -Match '✓'
	}

	It "leaves '✓ label' when a labelled spinner is stopped normally" {
		$captured = New-Object System.Collections.Generic.List[string]
		Mock Write-Host { if ($null -ne $Object) { $captured.Add([string]$Object) } else { $captured.Add("") } }

		$h = Loading-Spinner -Start -Label "Working"
		Loading-Spinner -Stop -Spinner $h

		($captured -join "`n") | Should -Match '✓ Working'
	}

	It "erases (no checkmark) when stopped with -Discard, even if the spinner had a label" {
		$captured = New-Object System.Collections.Generic.List[string]
		Mock Write-Host { if ($null -ne $Object) { $captured.Add([string]$Object) } else { $captured.Add("") } }

		$h = Loading-Spinner -Start -Label "Applying layout"
		Loading-Spinner -Stop -Spinner $h -Discard

		($captured -join "`n") | Should -Not -Match '✓'
	}

	It "always emits one blank line before the first spinner frame" {
		$captured = New-Object System.Collections.Generic.List[string]
		Mock Write-Host { if ($null -ne $Object) { $captured.Add([string]$Object) } else { $captured.Add("") } }

		$h = Loading-Spinner -Start -Label "Work"
		Loading-Spinner -Stop -Spinner $h

		# The very first thing written is the leading newline (an empty string),
		# so the spinner always animates on its own fresh line.
		$captured[0] | Should -Be ""
	}

	It "renders the nested label and reverts to the parent on stop (single line)" {
		$captured = New-Object System.Collections.Generic.List[string]
		Mock Write-Host { if ($null -ne $Object) { $captured.Add([string]$Object) } }

		$outer = Loading-Spinner -Start -Label "Outer"
		$inner = Loading-Spinner -Start -Label "Starting FancyZones..."
		Loading-Spinner -Stop -Spinner $inner
		Loading-Spinner -Stop -Spinner $outer

		$joined = ($captured -join "`n")
		# The nested label was drawn at least once...
		$joined | Should -Match 'Starting FancyZones'
		# ...and the final teardown of the empty-label outer spinner is an erase
		# (spaces + carriage returns), never a stray checkmark or leftover glyph.
		$captured[$captured.Count - 1] | Should -Not -Match 'Starting FancyZones'
	}
}
