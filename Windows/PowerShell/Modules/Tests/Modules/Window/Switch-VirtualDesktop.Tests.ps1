#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Window\Functions\Invoke-VirtualDesktopOperation.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Get-CurrentVirtualDesktopIndex.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Switch-VirtualDesktop.ps1")
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeVirtualDesktop.ps1")
	function Clear-WindowCache { }
}

Describe "Switch-VirtualDesktop" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Start-Sleep { }
		Mock Clear-WindowCache { }
		$null = New-FakeVirtualDesktopSession -DesktopCount 4 -CurrentIndex 0
	}

	It "switches, confirms the desktop is showing, and clears the window cache" {
		Switch-VirtualDesktop -Index 2 | Should -BeTrue

		$global:FakeVirtualDesktop.CurrentIndex | Should -Be 2
		@($global:FakeVirtualDesktop.SwitchLog) | Should -Be @(2)
		Should -Invoke Clear-WindowCache -Times 1 -Exactly
	}

	It "reports a desktop that is already showing as switched without asking the manager to switch" {
		$global:FakeVirtualDesktop.CurrentIndex = 3

		Switch-VirtualDesktop -Index 3 | Should -BeTrue
		$global:FakeVirtualDesktop.SwitchLog.Count | Should -Be 0
		Should -Invoke Clear-WindowCache -Times 0
	}

	It "retries when the switch silently does not land, then resets the session and lands it" {
		# A stale proxy: Switch-Desktop returns without error and nothing changes. Three attempts
		# fail, the session reset makes the fourth stick.
		Mock Switch-Desktop {
			param($Desktop)
			if ($global:FakeVirtualDesktop.ResetCount -gt 0) { $global:FakeVirtualDesktop.CurrentIndex = [int]$Desktop }
		}

		Switch-VirtualDesktop -Index 1 -TimeoutMs 0 -MaxAttempts 3 | Should -BeTrue
		$global:FakeVirtualDesktop.ResetCount | Should -Be 1
		Should -Invoke Switch-Desktop -Times 4 -Exactly
	}

	It "returns false when the desktop never comes on screen, even after the reset" {
		Mock Switch-Desktop { param($Desktop) }

		Switch-VirtualDesktop -Index 1 -TimeoutMs 0 -MaxAttempts 2 | Should -BeFalse
		Should -Invoke Clear-WindowCache -Times 0
	}

	It "recovers an RPC failure inside the switch itself through the operation seam" {
		Set-FakeVirtualDesktopFailure -Cmdlet Switch-Desktop -Times 1

		Switch-VirtualDesktop -Index 2 | Should -BeTrue
		$global:FakeVirtualDesktop.CurrentIndex | Should -Be 2
	}

	It "throws when the VirtualDesktop module is not available at all" {
		$null = New-FakeVirtualDesktopSession -DesktopCount 2 -ModuleUnavailable

		{ Switch-VirtualDesktop -Index 1 } | Should -Throw '*VirtualDesktop module is not available*'
	}
}
