#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. (Join-Path $ModuleRoot "Window\Functions\Ensure-DesktopVisible.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Get-WindowDesktopIndex.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Switch-VirtualDesktop.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Get-CurrentVirtualDesktopIndex.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Invoke-VirtualDesktopOperation.ps1")
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeVirtualDesktop.ps1")

	function Clear-WindowCache { }
}

Describe "Ensure-DesktopVisible" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Start-Sleep { }
		Mock Clear-WindowCache { }

		# Desktop 1 is showing; window 407 lives on desktop 3.
		$null = New-FakeVirtualDesktopSession -DesktopCount 4 -CurrentIndex 1 -WindowDesktops @{ 407 = 3 }
	}

	Context "Switching to a window's desktop" {
		It "switches and reports the desktop that was showing" {
			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -Be 1

			@($global:FakeVirtualDesktop.SwitchLog) | Should -Be @(3)
			$global:FakeVirtualDesktop.CurrentIndex | Should -Be 3
		}

		It "does nothing when the window's desktop is already showing" {
			$global:FakeVirtualDesktop.CurrentIndex = 3

			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -BeNullOrEmpty

			$global:FakeVirtualDesktop.SwitchLog.Count | Should -Be 0
		}

		It "reports nothing when the window's desktop cannot be resolved" {
			# Handle 999 is unknown to the desktop manager - a shell window, or one that closed.
			Ensure-DesktopVisible -WindowHandle ([IntPtr]999) | Should -BeNullOrEmpty

			$global:FakeVirtualDesktop.SwitchLog.Count | Should -Be 0
		}

		It "invalidates the window cache after switching, since handles were enumerated elsewhere" {
			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Out-Null

			Should -Invoke Clear-WindowCache -Times 1
		}
	}

	Context "Switching to an explicit index" {
		It "switches to the requested desktop and reports the previous one" {
			Ensure-DesktopVisible -DesktopIndex 3 | Should -Be 1

			@($global:FakeVirtualDesktop.SwitchLog) | Should -Be @(3)
		}

		It "round-trips the value returned by the window form" {
			$previous = Ensure-DesktopVisible -WindowHandle ([IntPtr]407)
			$global:FakeVirtualDesktop.SwitchLog.Clear()

			Ensure-DesktopVisible -DesktopIndex $previous | Out-Null

			@($global:FakeVirtualDesktop.SwitchLog) | Should -Be @(1)
			$global:FakeVirtualDesktop.CurrentIndex | Should -Be 1
		}

		It "reports desktop 0 as the previous desktop, not as nothing" {
			$global:FakeVirtualDesktop.CurrentIndex = 0

			Ensure-DesktopVisible -DesktopIndex 3 | Should -Be 0
		}
	}

	Context "Unreliable virtual desktop state" {
		It "recovers a stale COM proxy through a session reset when the switch silently does not take" {
			# A long-running shell can hold a proxy whose Switch-Desktop returns without error and
			# changes nothing; the reset makes the next switch stick.
			Mock Switch-Desktop {
				param($Desktop)
				if ($global:FakeVirtualDesktop.ResetCount -gt 0) { $global:FakeVirtualDesktop.CurrentIndex = [int]$Desktop }
			}

			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -Be 1

			$global:FakeVirtualDesktop.ResetCount | Should -Be 1
			$global:FakeVirtualDesktop.CurrentIndex | Should -Be 3
		}

		It "recovers an RPC failure inside the switch through the operation seam" {
			Set-FakeVirtualDesktopFailure -Cmdlet Switch-Desktop -Times 1

			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -Be 1

			$global:FakeVirtualDesktop.CurrentIndex | Should -Be 3
		}

		It "reports nothing when the desktop cannot be brought on screen" {
			Mock Switch-Desktop { param($Desktop) }

			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -BeNullOrEmpty

			Should -Invoke Clear-WindowCache -Times 0
		}

		It "reports nothing when a switch throws every time" {
			Mock Switch-Desktop { throw 'RPC server is unavailable' }

			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -BeNullOrEmpty
		}

		It "reports nothing rather than throwing when the current-desktop lookup fails" {
			Mock Get-CurrentDesktop { throw 'The RPC server is unavailable. (Exception from HRESULT: 0x800706BA)' }

			{ Ensure-DesktopVisible -WindowHandle ([IntPtr]407) } | Should -Not -Throw
			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -BeNullOrEmpty
			$global:FakeVirtualDesktop.SwitchLog.Count | Should -Be 0
		}

		It "reports nothing when the VirtualDesktop module is not available" {
			$null = New-FakeVirtualDesktopSession -DesktopCount 4 -CurrentIndex 1 -WindowDesktops @{ 407 = 3 } -ModuleUnavailable

			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -BeNullOrEmpty
			Ensure-DesktopVisible -DesktopIndex 3 | Should -BeNullOrEmpty

			$global:FakeVirtualDesktop.SwitchLog.Count | Should -Be 0
		}
	}
}
