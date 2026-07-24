#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force

	# Get-DesktopList comes from the optional VirtualDesktop module, absent on CI runners.
	# Global stub so Mock -ModuleName Window can attach; no-op where the real module is installed.
	# Removed in AfterAll so it never leaks to other tests.
	if (-not (Get-Command Get-DesktopList -ErrorAction SilentlyContinue)) {
		function global:Get-DesktopList { [CmdletBinding()] param() }
	}
}

AfterAll {
	if (Test-Path 'function:\Get-DesktopList') { Remove-Item 'function:\Get-DesktopList' -Force -ErrorAction SilentlyContinue }
}

Describe "Get-NextAvailableDesktopIndex" {
	BeforeEach {
		Mock Write-Host { } -ModuleName Window
		Mock Write-Warning { } -ModuleName Window
	}

	Context "When VirtualDesktop module is available" {
		It "Should return count of existing desktops as next index" {
			Mock Import-VirtualDesktopModule { $true } -ModuleName Window
			Mock Get-DesktopList { @(1, 2, 3) } -ModuleName Window

			$result = Get-NextAvailableDesktopIndex

			$result | Should -Be 3
		}

		It "Should return 1 when only one desktop exists" {
			Mock Import-VirtualDesktopModule { $true } -ModuleName Window
			Mock Get-DesktopList { @(1) } -ModuleName Window

			$result = Get-NextAvailableDesktopIndex

			$result | Should -Be 1
		}

		It "Should use the cached module loader instead of a Get-Module disk scan" {
			Mock Import-VirtualDesktopModule { $true } -ModuleName Window
			Mock Get-Module { throw "Get-Module -ListAvailable must not be called (disk scan per call)" } -ModuleName Window
			Mock Get-DesktopList { @(1, 2) } -ModuleName Window

			$result = Get-NextAvailableDesktopIndex

			$result | Should -Be 2
			Should -Invoke Import-VirtualDesktopModule -ModuleName Window -Times 1 -Exactly
		}
	}

	Context "When VirtualDesktop module is not available" {
		It "Should return `$null and warn (never 0 - alongside would clobber desktop 0)" {
			Mock Import-VirtualDesktopModule { $false } -ModuleName Window

			$result = Get-NextAvailableDesktopIndex

			$result | Should -BeNullOrEmpty
			Should -Invoke Write-Warning -ModuleName Window
		}
	}

	Context "When Get-DesktopList throws" {
		It "Should return `$null gracefully so callers can abort instead of using offset 0" {
			Mock Import-VirtualDesktopModule { $true } -ModuleName Window
			Mock Get-DesktopList { throw "COM error" } -ModuleName Window

			$result = Get-NextAvailableDesktopIndex

			$result | Should -BeNullOrEmpty
			Should -Invoke Write-Warning -ModuleName Window
		}
	}
}
