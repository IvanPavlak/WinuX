#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. (Join-Path $ModuleRoot "Window\Functions\Ensure-DesktopVisible.ps1")

	# VirtualDesktop ships these; on a machine (or CI agent) without the module they do not exist
	# at all, and Mock cannot attach to an absent command - so stub first, mock second.
	function Switch-Desktop { param($Desktop) }
	function Get-CurrentDesktop { }
	function Get-DesktopIndex { param($Desktop) 0 }
	function Get-DesktopFromWindow { param($Hwnd) }
	function Wait-DesktopSwitch { param($TargetDesktopIndex) $true }
	function Reset-VirtualDesktopState { $false }
	function Import-VirtualDesktopModule { param([switch]$Silent) $true }
	function Clear-WindowCache { }
}

Describe "Ensure-DesktopVisible" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Clear-WindowCache { }
		Mock Reset-VirtualDesktopState { $false }
		Mock Import-VirtualDesktopModule { $true }

		$script:visibleIndex = 1
		$script:switchTargets = @()

		Mock Get-CurrentDesktop { [PSCustomObject]@{ Kind = 'current' } }
		Mock Get-DesktopFromWindow { param($Hwnd) [PSCustomObject]@{ Kind = 'window' } }
		Mock Get-DesktopIndex {
			param($Desktop)
			if ($Desktop.Kind -eq 'current') { $script:visibleIndex } else { 3 }
		}
		Mock Switch-Desktop {
			param($Desktop)
			$script:switchTargets += $Desktop
			$script:visibleIndex = $Desktop
		}
		Mock Wait-DesktopSwitch { $true }
	}

	Context "Switching to a window's desktop" {
		It "switches and reports the desktop that was showing" {
			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -Be 1

			$script:switchTargets | Should -Be @(3)
		}

		It "does nothing when the window's desktop is already showing" {
			$script:visibleIndex = 3

			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -BeNullOrEmpty

			Should -Invoke Switch-Desktop -Times 0
		}

		It "reports nothing when the window's desktop cannot be resolved" {
			Mock Get-DesktopFromWindow { $null }

			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -BeNullOrEmpty

			Should -Invoke Switch-Desktop -Times 0
		}

		It "invalidates the window cache after switching, since handles were enumerated elsewhere" {
			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Out-Null

			Should -Invoke Clear-WindowCache -Times 1
		}
	}

	Context "Switching to an explicit index" {
		It "switches to the requested desktop and reports the previous one" {
			Ensure-DesktopVisible -DesktopIndex 3 | Should -Be 1

			$script:switchTargets | Should -Be @(3)
		}

		It "round-trips the value returned by the window form" {
			$previous = Ensure-DesktopVisible -WindowHandle ([IntPtr]407)
			$script:switchTargets = @()

			Ensure-DesktopVisible -DesktopIndex $previous | Out-Null

			$script:switchTargets | Should -Be @(1)
		}
	}

	Context "Unreliable virtual desktop state" {
		It "retries a switch that does not take" {
			$script:attempts = 0
			Mock Wait-DesktopSwitch { $script:attempts++; $script:attempts -ge 2 }

			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -Be 1

			Should -Invoke Switch-Desktop -Times 2
		}

		It "recovers a stale COM proxy through a module reset" {
			# A long-running shell can hold a proxy whose Switch-Desktop silently no-ops.
			Mock Wait-DesktopSwitch { $false }
			$script:resetDone = $false
			Mock Reset-VirtualDesktopState { $script:resetDone = $true; $true }

			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Out-Null

			$script:resetDone | Should -BeTrue
		}

		It "reports nothing when the desktop cannot be brought on screen" {
			Mock Wait-DesktopSwitch { $false }

			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -BeNullOrEmpty
		}

		It "reports nothing when a switch throws every time" {
			Mock Switch-Desktop { throw 'RPC server is unavailable' }

			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -BeNullOrEmpty
		}

		It "reports nothing rather than throwing when the desktop lookup fails" {
			Mock Get-CurrentDesktop { throw '0x800706BA' }

			{ Ensure-DesktopVisible -WindowHandle ([IntPtr]407) } | Should -Not -Throw
			Ensure-DesktopVisible -WindowHandle ([IntPtr]407) | Should -BeNullOrEmpty
		}
	}
}
