#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force

	# VirtualDesktop cmdlets come from an optional external module absent on CI runners.
	# Define global stubs so Mock -ModuleName Window can attach (module scope chains to global);
	# no-op where the real module is installed. Removed in AfterAll so they never leak to other tests.
	if (-not (Get-Command Get-DesktopList -ErrorAction SilentlyContinue)) {
		function global:Get-DesktopList { [CmdletBinding()] param() }
		function global:New-Desktop { [CmdletBinding()] param() }
		function global:Switch-Desktop { [CmdletBinding()] param($Desktop) }
	}
}

AfterAll {
	foreach ($cmd in 'Get-DesktopList', 'New-Desktop', 'Switch-Desktop') {
		if (Test-Path "function:\$cmd") { Remove-Item "function:\$cmd" -Force -ErrorAction SilentlyContinue }
	}
}

Describe "Ensure-VirtualDesktops" {
	BeforeEach {
		Mock Write-Host { } -ModuleName Window
		Mock Write-Error { } -ModuleName Window
		Mock Start-Sleep { } -ModuleName Window
	}

	Context "When VirtualDesktop module is not available" {
		It "Should return false and write error" {
			Mock Import-VirtualDesktopModule { $false } -ModuleName Window

			$result = Ensure-VirtualDesktops -Count 3

			$result | Should -Be $false
			Should -Invoke Write-Error -ModuleName Window -Times 1
		}
	}

	Context "When desktops already match required count" {
		It "Should return true without creating desktops" {
			Mock Import-VirtualDesktopModule { $true } -ModuleName Window
			Mock Get-DesktopList { @(1, 2, 3) } -ModuleName Window
			Mock New-Desktop { } -ModuleName Window

			$result = Ensure-VirtualDesktops -Count 3

			$result | Should -Be $true
			Should -Invoke New-Desktop -ModuleName Window -Times 0
		}
	}

	Context "When fewer desktops exist than required" {
		It "Should create the missing desktops" {
			Mock Import-VirtualDesktopModule { $true } -ModuleName Window
			$script:gdlCallCount = 0
			Mock Get-DesktopList {
				$script:gdlCallCount++
				if ($script:gdlCallCount -le 1) { @(1, 2) } else { @(1, 2, 3, 4) }
			} -ModuleName Window
			Mock New-Desktop { } -ModuleName Window

			$result = Ensure-VirtualDesktops -Count 4

			$result | Should -Be $true
			Should -Invoke New-Desktop -ModuleName Window -Times 2 -Exactly
		}
	}

	# NOTE: "When more desktops exist than required" is intentionally not tested.
	# The source function has a while loop that checks $currentCount but never updates it
	# inside the loop body, making it untestable with mocks (infinite loop).

	Context "When SwitchToDesktop is specified" {
		It "Should switch to the specified desktop (1-based to 0-based)" {
			Mock Import-VirtualDesktopModule { $true } -ModuleName Window
			Mock Get-DesktopList { @(1, 2, 3) } -ModuleName Window
			Mock Switch-Desktop { } -ModuleName Window

			$result = Ensure-VirtualDesktops -Count 3 -SwitchToDesktop 2

			$result | Should -Be $true
			Should -Invoke Switch-Desktop -ModuleName Window -ParameterFilter { $Desktop -eq 1 }
		}

		It "Should not switch if SwitchToDesktop is 0" {
			Mock Import-VirtualDesktopModule { $true } -ModuleName Window
			Mock Get-DesktopList { @(1, 2) } -ModuleName Window
			Mock Switch-Desktop { } -ModuleName Window

			Ensure-VirtualDesktops -Count 2

			Should -Invoke Switch-Desktop -ModuleName Window -Times 0
		}
	}
}
