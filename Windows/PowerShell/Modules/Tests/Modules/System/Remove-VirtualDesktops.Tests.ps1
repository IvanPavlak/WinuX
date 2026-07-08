#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"
	$HelperFunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$HelperFunctionsPath\Invoke-WithRetry.ps1"
	. "$HelperFunctionsPath\Invoke-WithOptionalRetry.ps1"
	. "$HelperFunctionsPath\Get-RpcRetryPolicy.ps1"
	. "$FunctionsPath\Remove-VirtualDesktops.ps1"

	function Reset-VirtualDesktopState { }

	# VirtualDesktop cmdlets come from an optional external module absent on CI runners.
	# Stub the ones these tests mock so Mock can attach (no-op where the real module exists).
	if (-not (Get-Command Get-DesktopList -ErrorAction SilentlyContinue)) {
		function Get-DesktopList { [CmdletBinding()] param() }
		function Remove-Desktop { [CmdletBinding()] param($Desktop) }
		function Get-DesktopFromWindow { [CmdletBinding()] param($Hwnd) }
		function Get-DesktopIndex { [CmdletBinding()] param([Parameter(Position = 0)]$Desktop) }
	}
}

Describe "Remove-VirtualDesktops" {
	BeforeEach {
		$script:desktopListCalls = 0
		# On CI the VirtualDesktop module is absent, so the real Import-VirtualDesktopModule
		# returns $false and the function early-exits. Mock it so the removal logic is exercised
		# (locally the real module is installed, so this matches local behavior).
		Mock Import-VirtualDesktopModule { $true }
		Mock Write-Host { }
		Mock Write-LogDebug { }
		Mock Write-LogSuccess { }
		Mock Write-LogList { }
		Mock Test-LogVerbose { $false }
		Mock Start-Sleep { }
		Mock Get-RpcRetryPolicy { @{ MaxAttempts = 3; InitialDelayMs = 0 } }
		Mock Get-DesktopFromWindow { $null }
		Mock Get-DesktopIndex { -1 }
		Mock Reset-VirtualDesktopState { $true }
	}

	Context "Default mode (remove all except desktop 0)" {
		It "returns false when virtual desktop cmdlets are unavailable" {
			Mock Get-DesktopList { throw "The term 'Get-DesktopList' is not recognized as a name of a cmdlet" }
			Mock Remove-Desktop { }

			$result = Remove-VirtualDesktops

			$result | Should -Be $false
			Should -Invoke Remove-Desktop -Times 0
		}

		It "removes desktops from right to left until a single desktop remains" {
			Mock Get-DesktopList {
				$script:desktopListCalls++
				switch ($script:desktopListCalls) {
					1 { @(0, 1, 2) }
					2 { @(0, 1) }
					default { @(0) }
				}
			}
			Mock Remove-Desktop { }

			Remove-VirtualDesktops

			Should -Invoke Remove-Desktop -Times 2 -Exactly
			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 2 }
			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 1 }
		}

		It "lists the removed desktops in the normal-mode summary" {
			Mock Get-DesktopList {
				$script:desktopListCalls++
				switch ($script:desktopListCalls) {
					1 { @(0, 1, 2) }
					2 { @(0, 1) }
					default { @(0) }
				}
			}
			Mock Remove-Desktop { }

			Remove-VirtualDesktops

			Should -Invoke Write-LogSuccess -Times 1 -Exactly -ParameterFilter { $Message -eq "Removed 2 virtual desktop(s)!" }
			Should -Invoke Write-LogList -Times 1 -Exactly -ParameterFilter {
				$Items.Count -eq 2 -and $Items[0] -eq "Desktop [2]" -and $Items[1] -eq "Desktop [1]"
			}
		}

		It "returns false when desktop removal throws" {
			Mock Get-DesktopList { @(0, 1) }
			Mock Remove-Desktop { throw "desktop removal failed" }

			$result = Remove-VirtualDesktops

			$result | Should -Be $false
		}

		It "requests a live RPC probe before desktop cleanup" {
			Mock Get-DesktopList { @(0) }
			Mock Remove-Desktop { }

			Remove-VirtualDesktops

			Should -Invoke Get-RpcRetryPolicy -Times 1 -Exactly -ParameterFilter {
				$OperationLabel -eq "desktop cleanup" -and $Probe -and $MaxAttempts -eq 5 -and $InitialDelayMs -eq 250
			}
		}

		It "resets VirtualDesktop state when an RPC-unavailable call is retried" {
			Mock Get-DesktopList {
				$script:desktopListCalls++
				if ($script:desktopListCalls -eq 1) {
					throw "The RPC server is unavailable. (0x800706BA)"
				}
				@(0)
			}
			Mock Remove-Desktop { }

			Remove-VirtualDesktops

			$script:desktopListCalls | Should -Be 2
			Should -Invoke Reset-VirtualDesktopState -Times 1 -Exactly
		}
	}

	Context "EmptyOnly mode" {
		It "does nothing when only one desktop exists" {
			Mock Get-DesktopList { @(0) }
			Mock Remove-Desktop { }

			Remove-VirtualDesktops -EmptyOnly

			Should -Invoke Remove-Desktop -Times 0
		}

		It "removes empty desktops and keeps occupied desktops" {
			Mock Get-DesktopList {
				$script:desktopListCalls++
				if ($script:desktopListCalls -eq 1) { @(0, 1, 2, 3) }
				else { @(0, 1, 3) }
			}
			Mock Get-Command {
				[PSCustomObject]@{ Name = 'Get-WindowHandle' }
			} -ParameterFilter { $Name -eq 'Get-WindowHandle' }
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]11 },
					[PSCustomObject]@{ Handle = [IntPtr]33 }
				)
			}
			Mock Get-DesktopFromWindow {
				if ($Hwnd -eq [IntPtr]11) { 'desktop-1' }
				elseif ($Hwnd -eq [IntPtr]33) { 'desktop-3' }
				else { $null }
			}
			Mock Get-DesktopIndex {
				if ($Desktop -eq 'desktop-1') { 1 }
				elseif ($Desktop -eq 'desktop-3') { 3 }
				else { -1 }
			}
			Mock Remove-Desktop { }

			Remove-VirtualDesktops -EmptyOnly

			Should -Invoke Remove-Desktop -Times 2 -Exactly
			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 2 }
			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 0 }
		}

		It "falls back to process MainWindowHandle enumeration when Get-WindowHandle is unavailable" {
			Mock Get-DesktopList {
				$script:desktopListCalls++
				if ($script:desktopListCalls -eq 1) { @(0, 1, 2) }
				else { @(0, 1) }
			}
			Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-WindowHandle' }
			Mock Get-Process {
				@(
					[PSCustomObject]@{ MainWindowHandle = [IntPtr]::Zero },
					[PSCustomObject]@{ MainWindowHandle = [IntPtr]55 }
				)
			}
			Mock Get-DesktopFromWindow {
				if ($Hwnd -eq [IntPtr]55) { 'desktop-1' } else { $null }
			}
			Mock Get-DesktopIndex {
				if ($Desktop -eq 'desktop-1') { 1 } else { -1 }
			}
			Mock Remove-Desktop { }

			Remove-VirtualDesktops -EmptyOnly

			Should -Invoke Get-Process -Times 1
			Should -Invoke Remove-Desktop -Times 2 -Exactly
			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 2 }
			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 0 }
		}
	}
}
