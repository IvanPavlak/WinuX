#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. (Join-Path $ModuleRoot "Window\Functions\Ensure-VirtualDesktops.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Invoke-VirtualDesktopOperation.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Switch-VirtualDesktop.ps1")
	. (Join-Path $ModuleRoot "Window\Functions\Get-CurrentVirtualDesktopIndex.ps1")
	. (Join-Path $ModuleRoot "Tests\Modules\Support\FakeVirtualDesktop.ps1")

	$script:WindowModuleDelays = @{ VirtualDesktopMs = 0 }
	function Clear-WindowCache { }
}

Describe "Ensure-VirtualDesktops" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-Error { }
		Mock Write-LogDebug { }
		Mock Write-LogWarning { }
		Mock Write-LogStep { }
		Mock Start-Sleep { }
		Mock Clear-WindowCache { }

		$null = New-FakeVirtualDesktopSession -DesktopCount 3 -CurrentIndex 0
	}

	Context "When VirtualDesktop module is not available" {
		It "Should return false and write error" {
			$null = New-FakeVirtualDesktopSession -DesktopCount 3 -ModuleUnavailable

			$result = Ensure-VirtualDesktops -Count 3

			$result | Should -Be $false
			Should -Invoke Write-Error -Times 1
		}
	}

	Context "When desktops already match required count" {
		It "Should return true without creating desktops" {
			$result = Ensure-VirtualDesktops -Count 3

			$result | Should -Be $true
			$global:FakeVirtualDesktop.CreatedCount | Should -Be 0
			$global:FakeVirtualDesktop.RemovedLog.Count | Should -Be 0
		}
	}

	Context "RPC preflight" {
		It "Requests a live RPC probe with the shared desktop retry budget, once, before the first call" {
			Mock Get-RpcRetryPolicy { @{ MaxAttempts = 5; InitialDelayMs = 0 } }

			$null = Ensure-VirtualDesktops -Count 3

			Should -Invoke Get-RpcRetryPolicy -Times 1 -Exactly -ParameterFilter {
				$OperationLabel -eq "ensuring virtual desktops" -and $Probe -and $MaxAttempts -eq 5 -and $InitialDelayMs -eq 250
			}
		}
	}

	Context "When fewer desktops exist than required" {
		It "Should create the missing desktops" {
			$null = New-FakeVirtualDesktopSession -DesktopCount 2

			$result = Ensure-VirtualDesktops -Count 4

			$result | Should -Be $true
			$global:FakeVirtualDesktop.CreatedCount | Should -Be 2
			$global:FakeVirtualDesktop.Desktops.Count | Should -Be 4
		}

		It "Should return false when the desktops did not appear" {
			# The manager accepts New-Desktop but the count never grows: a stale session.
			$null = New-FakeVirtualDesktopSession -DesktopCount 2
			Mock New-Desktop { }

			$result = Ensure-VirtualDesktops -Count 3

			$result | Should -Be $false
			Should -Invoke Write-Error -Times 1 -ParameterFilter { $Message -match 'Expected \[3\], found \[2\]' }
		}
	}

	Context "When more desktops exist than required" {
		It "Should remove the extra desktops from the right and land on desktop 0" {
			$null = New-FakeVirtualDesktopSession -DesktopCount 5 -CurrentIndex 4

			$result = Ensure-VirtualDesktops -Count 3

			$result | Should -Be $true
			@($global:FakeVirtualDesktop.RemovedLog) | Should -Be @(4, 3)
			$global:FakeVirtualDesktop.Desktops.Count | Should -Be 3
			$global:FakeVirtualDesktop.CurrentIndex | Should -Be 0
		}

		It "Should return false when a removal fails" {
			$null = New-FakeVirtualDesktopSession -DesktopCount 5
			Mock Remove-Desktop { throw 'desktop removal failed' }

			$result = Ensure-VirtualDesktops -Count 3

			$result | Should -Be $false
		}
	}

	Context "When a desktop operation fails with an RPC error" {
		It "Resets the VirtualDesktop state between retries and succeeds" {
			$null = New-FakeVirtualDesktopSession -DesktopCount 2
			Set-FakeVirtualDesktopFailure -Cmdlet New-Desktop -Times 1

			$result = Ensure-VirtualDesktops -Count 3

			$result | Should -Be $true
			$global:FakeVirtualDesktop.CreatedCount | Should -Be 1
			$global:FakeVirtualDesktop.Desktops.Count | Should -Be 3
			$global:FakeVirtualDesktop.ResetCount | Should -Be 1
		}

		It "Recovers a stale session on the very first count" {
			Set-FakeVirtualDesktopFailure -Cmdlet Get-DesktopCount -Times 1

			$result = Ensure-VirtualDesktops -Count 3

			$result | Should -Be $true
			$global:FakeVirtualDesktop.ResetCount | Should -Be 1
		}

		It "Does not reset the VirtualDesktop state for non-RPC failures and reports them" {
			# A non-RPC error is the caller's business: the seam rethrows it at once, unretried.
			$null = New-FakeVirtualDesktopSession -DesktopCount 2
			Mock New-Desktop { throw 'some unrelated transient failure' }

			$result = Ensure-VirtualDesktops -Count 3

			$result | Should -Be $false
			Should -Invoke New-Desktop -Times 1 -Exactly
			$global:FakeVirtualDesktop.ResetCount | Should -Be 0
			Should -Invoke Write-Error -Times 1 -ParameterFilter { $Message -like "*Failed to manage virtual desktops*" }
		}
	}

	Context "When SwitchToDesktop is specified" {
		It "Should switch to the specified desktop (1-based to 0-based)" {
			$result = Ensure-VirtualDesktops -Count 3 -SwitchToDesktop 2

			$result | Should -Be $true
			@($global:FakeVirtualDesktop.SwitchLog) | Should -Be @(1)
			$global:FakeVirtualDesktop.CurrentIndex | Should -Be 1
		}

		It "Should not switch if SwitchToDesktop is 0" {
			$null = Ensure-VirtualDesktops -Count 3

			$global:FakeVirtualDesktop.SwitchLog.Count | Should -Be 0
		}

		It "Should not switch to a desktop beyond the requested count" {
			$null = Ensure-VirtualDesktops -Count 3 -SwitchToDesktop 4

			$global:FakeVirtualDesktop.SwitchLog.Count | Should -Be 0
		}
	}
}
