#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. (Join-Path $ModuleRoot "Window\Functions\Get-WindowDesktopIndex.ps1")

	# VirtualDesktop ships these; on a machine (or CI agent) without the module they do not exist at
	# all, and Mock cannot attach to an absent command - so stub first, mock second.
	function Get-DesktopFromWindow { param($Hwnd) }
	function Get-DesktopIndex { param($Desktop) 0 }
	function Import-VirtualDesktopModule { param([switch]$Silent) $true }
}

Describe "Get-WindowDesktopIndex" {
	BeforeEach {
		Mock Write-LogDebug { }
		Mock Import-VirtualDesktopModule { $true }
		Mock Get-DesktopFromWindow { param($Hwnd) [PSCustomObject]@{ Kind = 'desktop' } }
		Mock Get-DesktopIndex { 3 }
	}

	It "returns the desktop the window lives on" {
		Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) | Should -Be 3
	}

	It "reports desktop 0 as 0, not as nothing" {
		# The first desktop is the one a plain workspace lands on, and 0 is falsy - a caller that
		# tested truthiness instead of the value would silently lose the whole workspace.
		Mock Get-DesktopIndex { 0 }

		Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) | Should -Be 0
	}

	It "returns -1 for a zero handle without asking the desktop module" {
		Get-WindowDesktopIndex -WindowHandle ([IntPtr]::Zero) | Should -Be -1

		Should -Invoke Get-DesktopFromWindow -Times 0
	}

	It "returns -1 when the window has no resolvable desktop" {
		# Shell windows behave this way: TextInputHost always answers with nothing.
		Mock Get-DesktopFromWindow { $null }

		Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) | Should -Be -1
	}

	It "returns -1 rather than throwing when the lookup fails" {
		Mock Get-DesktopFromWindow { throw 'TYPE_E_ELEMENTNOTFOUND' }

		{ Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) } | Should -Not -Throw
		Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) | Should -Be -1
	}

	It "returns -1 when the index lookup itself fails" {
		Mock Get-DesktopIndex { throw '0x800706BA' }

		Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) | Should -Be -1
	}

	It "returns -1 when the index comes back null" {
		Mock Get-DesktopIndex { $null }

		Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) | Should -Be -1
	}

	It "does not retry a failed lookup" {
		# A window that cannot be resolved on its own merits cannot succeed on a second attempt, and
		# burning an RPC backoff ladder per window is the cost Remove-VirtualDesktops was fixed to stop
		# paying.
		Mock Get-DesktopFromWindow { throw 'TYPE_E_ELEMENTNOTFOUND' }

		Get-WindowDesktopIndex -WindowHandle ([IntPtr]407) | Out-Null

		Should -Invoke Get-DesktopFromWindow -Times 1 -Exactly
	}
}
