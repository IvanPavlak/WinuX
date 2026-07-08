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
			Mock Get-Module { [PSCustomObject]@{ Name = "VirtualDesktop" } } -ModuleName Window
			Mock Import-Module { } -ModuleName Window
			Mock Get-DesktopList { @(1, 2, 3) } -ModuleName Window

			$result = Get-NextAvailableDesktopIndex

			$result | Should -Be 3
		}

		It "Should return 1 when only one desktop exists" {
			Mock Get-Module { [PSCustomObject]@{ Name = "VirtualDesktop" } } -ModuleName Window
			Mock Import-Module { } -ModuleName Window
			Mock Get-DesktopList { @(1) } -ModuleName Window

			$result = Get-NextAvailableDesktopIndex

			$result | Should -Be 1
		}
	}

	Context "When VirtualDesktop module is not available" {
		It "Should return 0 and warn" {
			Mock Get-Module { $null } -ModuleName Window

			$result = Get-NextAvailableDesktopIndex

			$result | Should -Be 0
			Should -Invoke Write-Warning -ModuleName Window
		}
	}

	Context "When Get-DesktopList throws" {
		It "Should return 0 gracefully" {
			Mock Get-Module { [PSCustomObject]@{ Name = "VirtualDesktop" } } -ModuleName Window
			Mock Import-Module { } -ModuleName Window
			Mock Get-DesktopList { throw "COM error" } -ModuleName Window

			$result = Get-NextAvailableDesktopIndex

			$result | Should -Be 0
		}
	}
}
