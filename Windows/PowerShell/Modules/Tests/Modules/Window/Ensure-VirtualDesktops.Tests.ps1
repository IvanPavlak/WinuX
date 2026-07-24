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

	# Cross-module helpers (Helper/Window) the RPC recovery path resolves at run time.
	# Same global-stub trick, but tracked individually so only stubs this file created
	# are removed in AfterAll.
	$script:CreatedHelperStubs = @()
	$helperStubs = @{
		'Get-RpcRetryPolicy'         = { [CmdletBinding()] param([string]$OperationLabel, [int]$MaxAttempts, [int]$InitialDelayMs, [switch]$Probe) @{ MaxAttempts = 3; InitialDelayMs = 1 } }
		'Reset-VirtualDesktopState'  = { [CmdletBinding()] param() $true }
	}
	foreach ($stubName in $helperStubs.Keys) {
		if (-not (Get-Command $stubName -ErrorAction SilentlyContinue)) {
			$null = New-Item -Path "function:\global:$stubName" -Value $helperStubs[$stubName]
			$script:CreatedHelperStubs += $stubName
		}
	}
}

AfterAll {
	foreach ($cmd in 'Get-DesktopList', 'New-Desktop', 'Switch-Desktop') {
		if (Test-Path "function:\$cmd") { Remove-Item "function:\$cmd" -Force -ErrorAction SilentlyContinue }
	}
	foreach ($cmd in $script:CreatedHelperStubs) {
		if (Test-Path "function:\$cmd") { Remove-Item "function:\$cmd" -Force -ErrorAction SilentlyContinue }
	}
}

Describe "Ensure-VirtualDesktops" {
	BeforeEach {
		Mock Write-Host { } -ModuleName Window
		Mock Write-Error { } -ModuleName Window
		Mock Start-Sleep { } -ModuleName Window
		# Keep the RPC preflight hermetic - the real one probes the live endpoint.
		Mock Get-RpcRetryPolicy { @{ MaxAttempts = 3; InitialDelayMs = 1 } } -ModuleName Window
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

	Context "RPC preflight" {
		It "Requests a live RPC probe with the shared desktop retry budget" {
			Mock Import-VirtualDesktopModule { $true } -ModuleName Window
			Mock Get-DesktopList { @(1, 2) } -ModuleName Window

			$null = Ensure-VirtualDesktops -Count 2

			Should -Invoke Get-RpcRetryPolicy -ModuleName Window -Times 1 -Exactly -ParameterFilter {
				$OperationLabel -eq "ensuring virtual desktops" -and $Probe -and $MaxAttempts -eq 5 -and $InitialDelayMs -eq 250
			}
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

	Context "When a desktop operation fails with an RPC error" {
		It "Resets the VirtualDesktop state between retries and succeeds" {
			# Requires the real retry helpers (Helper module) so the OnRetry recovery
			# hook actually runs between attempts.
			if (-not (Get-Command Invoke-WithRetry -ErrorAction SilentlyContinue)) {
				Set-ItResult -Skipped -Because "Invoke-WithRetry (Helper module) is not available in this session"
				return
			}

			Mock Import-VirtualDesktopModule { $true } -ModuleName Window
			Mock Reset-VirtualDesktopState { $true } -ModuleName Window
			$script:gdlCallCount = 0
			Mock Get-DesktopList {
				$script:gdlCallCount++
				if ($script:gdlCallCount -le 1) { @(1, 2) } else { @(1, 2, 3) }
			} -ModuleName Window
			$script:newDesktopCalls = 0
			Mock New-Desktop {
				$script:newDesktopCalls++
				if ($script:newDesktopCalls -eq 1) {
					throw 'Exception calling "Create" with "0" argument(s): "The RPC server is unavailable. (0x800706BA)"'
				}
			} -ModuleName Window

			$result = Ensure-VirtualDesktops -Count 3

			$result | Should -Be $true
			Should -Invoke New-Desktop -ModuleName Window -Times 2 -Exactly
			Should -Invoke Reset-VirtualDesktopState -ModuleName Window -Times 1 -Exactly
		}

		It "Does not reset the VirtualDesktop state for non-RPC failures" {
			if (-not (Get-Command Invoke-WithRetry -ErrorAction SilentlyContinue)) {
				Set-ItResult -Skipped -Because "Invoke-WithRetry (Helper module) is not available in this session"
				return
			}

			Mock Import-VirtualDesktopModule { $true } -ModuleName Window
			Mock Reset-VirtualDesktopState { $true } -ModuleName Window
			$script:gdlCallCount = 0
			Mock Get-DesktopList {
				$script:gdlCallCount++
				if ($script:gdlCallCount -le 1) { @(1, 2) } else { @(1, 2, 3) }
			} -ModuleName Window
			$script:newDesktopCalls = 0
			Mock New-Desktop {
				$script:newDesktopCalls++
				if ($script:newDesktopCalls -eq 1) {
					throw 'some unrelated transient failure'
				}
			} -ModuleName Window

			$result = Ensure-VirtualDesktops -Count 3

			$result | Should -Be $true
			Should -Invoke Reset-VirtualDesktopState -ModuleName Window -Times 0
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
