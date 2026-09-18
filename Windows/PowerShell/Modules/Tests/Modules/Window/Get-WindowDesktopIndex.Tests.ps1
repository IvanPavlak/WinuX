#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. (Join-Path $ModuleRoot "Window\Functions\Invoke-VirtualDesktopOperation.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Get-WindowDesktopIndex.ps1")
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeVirtualDesktop.ps1")
}

Describe "Get-WindowDesktopIndex" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Start-Sleep { }
		$null = New-FakeVirtualDesktopSession -DesktopCount 4 -CurrentIndex 0 -WindowDesktops @{ 407 = 3; 408 = 0 }
	}

	It "returns the desktop the window lives on" {
		Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) | Should -Be 3
	}

	It "reports desktop 0 as 0, not as nothing" {
		# The first desktop is the one a plain workspace lands on, and 0 is falsy - a caller that
		# tested truthiness instead of the value would silently lose the whole workspace.
		Get-WindowDesktopIndex -WindowHandle ([IntPtr]408) | Should -Be 0
	}

	It "returns -1 for a zero handle without asking the desktop manager" {
		Mock Get-DesktopFromWindow { $null }

		Get-WindowDesktopIndex -WindowHandle ([IntPtr]::Zero) | Should -Be -1

		Should -Invoke Get-DesktopFromWindow -Times 0
	}

	It "returns -1 when the window has no resolvable desktop" {
		# Shell windows behave this way: TextInputHost always answers with nothing. Handle 999 is
		# unknown to the fake, so Get-DesktopFromWindow answers $null.
		Get-WindowDesktopIndex -WindowHandle ([IntPtr]999) | Should -Be -1
	}

	It "returns -1 rather than throwing when the lookup fails on its own merits" {
		Mock Get-DesktopFromWindow { throw 'TYPE_E_ELEMENTNOTFOUND' }

		{ Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) } | Should -Not -Throw
		Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) | Should -Be -1
	}

	It "returns -1 when the index comes back null" {
		Mock Get-DesktopIndex { $null }

		Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) | Should -Be -1
	}

	It "does not retry a lookup that failed on its own merits" {
		# A window that cannot be resolved cannot succeed on a second attempt, and burning an RPC
		# backoff ladder per window is the cost Remove-VirtualDesktops was fixed to stop paying.
		# The operation seam rethrows a non-RPC error at once, so the cmdlet runs exactly once.
		Mock Get-DesktopFromWindow { throw 'TYPE_E_ELEMENTNOTFOUND' }

		Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) | Out-Null

		Should -Invoke Get-DesktopFromWindow -Times 1 -Exactly
		$global:FakeVirtualDesktop.ResetCount | Should -Be 0
	}

	It "recovers a stale session once through the operation seam and still answers" {
		Set-FakeVirtualDesktopFailure -Cmdlet Get-DesktopFromWindow -Times 1

		Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) | Should -Be 3
		$global:FakeVirtualDesktop.ResetCount | Should -Be 1
	}

	It "returns -1 rather than throwing when the desktop manager stays unreachable after recovery" {
		Mock Get-DesktopFromWindow { throw 'The RPC server is unavailable. (Exception from HRESULT: 0x800706BA)' }

		{ Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) } | Should -Not -Throw
		Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) | Should -Be -1
	}

	It "returns -1 when the VirtualDesktop module is not available" {
		$null = New-FakeVirtualDesktopSession -ModuleUnavailable

		Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) | Should -Be -1
	}
}
