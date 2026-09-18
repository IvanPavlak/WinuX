#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. (Join-Path $ModuleRoot "Window\Functions\Move-WindowToVirtualDesktop.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Invoke-VirtualDesktopOperation.ps1")
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeVirtualDesktop.ps1")
}

Describe "Move-WindowToVirtualDesktop" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-Verbose { }
		Mock Write-Warning { }
		Mock Write-Error { }
		Mock Write-LogDebug { }
		Mock Start-Sleep { }
		Mock Test-LogVerbose { $false }

		# Three desktops; window 1234 sits on desktop 1.
		$null = New-FakeVirtualDesktopSession -DesktopCount 3 -CurrentIndex 0 -WindowDesktops @{ 1234 = 1 }
		$script:WindowModuleDelays = @{ VirtualDesktopMs = 0 }
	}

	It "returns true without any move when the window is already on the target desktop (fast path)" {
		# The common double-move case (early-stable callback + layout pass) must cost no COM move
		# and no settle delay.
		$result = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber 1

		$result | Should -BeTrue
		$global:FakeVirtualDesktop.MoveLog.Count | Should -Be 0
		Should -Invoke Start-Sleep -Times 0
	}

	It "moves the window to the 0-based desktop index and verifies it landed" {
		$result = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber 2

		$result | Should -BeTrue
		$global:FakeVirtualDesktop.MoveLog.Count | Should -Be 1
		$global:FakeVirtualDesktop.MoveLog[0].Hwnd | Should -Be 1234
		$global:FakeVirtualDesktop.MoveLog[0].Index | Should -Be 2
		$global:FakeVirtualDesktop.WindowDesktops[[int64]1234] | Should -Be 2
	}

	It "emits exactly one boolean on a successful move (Move-Window's Desktop output must not leak)" {
		$result = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber 2

		@($result).Count | Should -Be 1
		$result | Should -BeTrue
	}

	It "emits exactly one `$false when the move never lands - a leaked Desktop object would make the array truthy" {
		# Move-Window returns its Desktop object but the window stays where it was, so every
		# verification poll still reports desktop 1.
		# Regression: @(Desktop, $false) is truthy, so callers counted this failure as moved.
		Mock Move-Window { param($Desktop, $Hwnd) $Desktop }

		$result = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber 2

		Should -Invoke Move-Window -Times 1 -Exactly
		@($result).Count | Should -Be 1
		$result | Should -BeFalse
	}

	It "reports Moved in the script-scoped result only for a real move" {
		$null = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber 1
		$script:LastMoveWindowToVirtualDesktopResult.Moved | Should -BeFalse

		$null = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber 2
		$script:LastMoveWindowToVirtualDesktopResult.Moved | Should -BeTrue
	}

	It "moves a window whose current desktop cannot be resolved instead of giving up" {
		# A pinned or freshly created window answers no desktop; the fast path is skipped and the
		# move goes ahead.
		$result = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]5555) -DesktopNumber 2

		$result | Should -BeTrue
		$global:FakeVirtualDesktop.WindowDesktops[[int64]5555] | Should -Be 2
	}

	It "returns false and stops before move when desktop number equals desktop count (upper bound out of range)" {
		$result = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber 3

		$result | Should -BeFalse
		Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter { $Message -like "*out of range*" }
		$global:FakeVirtualDesktop.MoveLog.Count | Should -Be 0
	}

	It "returns false and stops before move when desktop number is negative" {
		$result = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber -1

		$result | Should -BeFalse
		Should -Invoke Write-Error -Times 1 -Exactly -ParameterFilter { $Message -like "*out of range*" }
		$global:FakeVirtualDesktop.MoveLog.Count | Should -Be 0
	}

	It "returns false with an install hint when the VirtualDesktop module is not available" {
		$null = New-FakeVirtualDesktopSession -DesktopCount 3 -WindowDesktops @{ 1234 = 1 } -ModuleUnavailable

		$result = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber 2

		$result | Should -BeFalse
		Should -Invoke Write-Warning -ParameterFilter { $Message -like "*Install-Module -Name VirtualDesktop*" }
		$global:FakeVirtualDesktop.MoveLog.Count | Should -Be 0
	}

	It "reconnects a stale session instead of reading a stale desktop count" {
		# A stale count of one desktop once made every window move report "out of range" on a
		# screen showing three. The seam resets the session and re-reads the count.
		Set-FakeVirtualDesktopFailure -Cmdlet Get-DesktopCount -Times 1

		$result = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber 2

		$result | Should -BeTrue
		$global:FakeVirtualDesktop.ResetCount | Should -Be 1
		Should -Invoke Write-Error -Times 0
	}

	It "recovers an RPC failure in the move itself" {
		Set-FakeVirtualDesktopFailure -Cmdlet Move-Window -Times 1

		$result = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber 2

		$result | Should -BeTrue
		$global:FakeVirtualDesktop.ResetCount | Should -Be 1
		$global:FakeVirtualDesktop.WindowDesktops[[int64]1234] | Should -Be 2
	}

	It "returns false when the desktop manager stays unreachable after recovery" {
		Mock Get-DesktopFromWindow { throw 'The RPC server is unavailable. (Exception from HRESULT: 0x800706BA)' }

		$result = Move-WindowToVirtualDesktop -WindowHandle ([IntPtr]1234) -DesktopNumber 2

		@($result).Count | Should -Be 1
		$result | Should -BeFalse
		$global:FakeVirtualDesktop.MoveLog.Count | Should -Be 0
		$global:FakeVirtualDesktop.ResetCount | Should -BeGreaterThan 0
	}
}
