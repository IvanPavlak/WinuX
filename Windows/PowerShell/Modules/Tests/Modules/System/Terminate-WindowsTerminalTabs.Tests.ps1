#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"
	$HelperFunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$HelperFunctionsPath\Countdown.ps1"
	. "$FunctionsPath\Invoke-TerminateWindowsTerminalTabsExit.ps1"
	. "$FunctionsPath\Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup.ps1"
	. "$FunctionsPath\Terminate-WindowsTerminalTabs.ps1"
}

Describe "Terminate-WindowsTerminalTabs" {
	BeforeEach {
		Mock Write-Host { }
		Mock Start-Sleep { }
		Mock Countdown { }
		Mock Add-Type { throw 'skip UI automation in tests' }
		Mock Get-WindowHandle { @() }
		Mock Start-Process { }
		Mock Stop-Process { }
	}

	Context "Main mode" {
		It "attempts hosting PID parent-chain resolution before selecting a terminal process" {
			$script:cimChain = @(
				[PSCustomObject]@{ ProcessId = $PID; ParentProcessId = 4321; Name = 'pwsh.exe' },
				[PSCustomObject]@{ ProcessId = 4321; ParentProcessId = 0; Name = 'WindowsTerminal.exe' }
			)
			Mock Get-CimInstance {
				if ($script:cimChain.Count -gt 0) {
					$result = $script:cimChain[0]
					$script:cimChain = @($script:cimChain | Select-Object -Skip 1)
					return $result
				}
				$null
			}

			Mock Get-Process { [PSCustomObject]@{ ProcessName = 'WindowsTerminal'; Id = 4321 } } -ParameterFilter { $PSBoundParameters.ContainsKey('Id') }
			Mock Get-Process {
				@(
					[PSCustomObject]@{ ProcessName = 'WindowsTerminal'; Id = 1001 },
					[PSCustomObject]@{ ProcessName = 'WindowsTerminal'; Id = 1002 }
				)
			} -ParameterFilter { -not $PSBoundParameters.ContainsKey('Id') }

			Terminate-WindowsTerminalTabs

			Should -Invoke Get-CimInstance -Times 2
			Should -Invoke Get-Process -Times 1 -Exactly -ParameterFilter { -not $PSBoundParameters.ContainsKey('Id') }
		}

		It "falls back to process-list selection when resolved hosting WT PID is no longer running" {
			$script:cimChain = @(
				[PSCustomObject]@{ ProcessId = $PID; ParentProcessId = 9876; Name = 'pwsh.exe' },
				[PSCustomObject]@{ ProcessId = 9876; ParentProcessId = 0; Name = 'WindowsTerminal.exe' }
			)
			Mock Get-CimInstance {
				if ($script:cimChain.Count -gt 0) {
					$result = $script:cimChain[0]
					$script:cimChain = @($script:cimChain | Select-Object -Skip 1)
					return $result
				}
				$null
			}

			Mock Get-Process { $null } -ParameterFilter { $PSBoundParameters.ContainsKey('Id') }
			Mock Get-Process {
				@(
					[PSCustomObject]@{ ProcessName = 'WindowsTerminal'; Id = 2222 },
					[PSCustomObject]@{ ProcessName = 'pwsh'; Id = 3333 }
				)
			} -ParameterFilter { -not $PSBoundParameters.ContainsKey('Id') }

			Terminate-WindowsTerminalTabs

			Should -Invoke Get-CimInstance -Times 2
			Should -Invoke Get-Process -Times 1 -Exactly -ParameterFilter { -not $PSBoundParameters.ContainsKey('Id') }
		}

		It "uses process-list fallback when hosting WT PID is not resolved" {
			Mock Get-CimInstance { $null }
			Mock Get-Process {
				@(
					[PSCustomObject]@{ ProcessName = 'WindowsTerminal'; Id = 7777 },
					[PSCustomObject]@{ ProcessName = 'pwsh'; Id = 8888 }
				)
			} -ParameterFilter { -not $PSBoundParameters.ContainsKey('Id') }

			Terminate-WindowsTerminalTabs

			Should -Invoke Get-Process -Times 0 -ParameterFilter { $PSBoundParameters.ContainsKey('Id') }
			Should -Invoke Get-Process -Times 1 -Exactly -ParameterFilter { -not $PSBoundParameters.ContainsKey('Id') }
		}

		It "returns cleanly when no WindowsTerminal process is found" {
			Mock Get-CimInstance { $null }
			Mock Get-Process { $null }
			Mock Get-WindowHandle { throw 'should not query windows when WT is missing' }

			Terminate-WindowsTerminalTabs

			Should -Invoke Get-WindowHandle -Times 0
		}
	}

	Context "OnlyCurrent mode" {
		It "exits through the process-exit seam when OnlyCurrent is specified" {
			$script:exitInvoked = $false
			Mock Invoke-TerminateWindowsTerminalTabsExit { $script:exitInvoked = $true }

			{ Terminate-WindowsTerminalTabs -OnlyCurrent } | Should -Not -Throw

			$script:exitInvoked | Should -BeTrue
		}

		It "waits before closing the current tab when CloseWaitSeconds is specified" {
			$script:exitInvoked = $false
			Mock Invoke-TerminateWindowsTerminalTabsExit { $script:exitInvoked = $true }

			{ Terminate-WindowsTerminalTabs -OnlyCurrent -CloseWaitSeconds 5 } | Should -Not -Throw

			Should -Invoke Countdown -Times 1 -ParameterFilter { $Seconds -eq 5 }
			$script:exitInvoked | Should -BeTrue
		}
	}

	Context "IncludeCurrent cleanup seam" {
		It "spawns cleanup process and invokes exit seam when WindowsTerminal process exists" {
			$script:exitInvoked = $false
			Mock Invoke-TerminateWindowsTerminalTabsExit { $script:exitInvoked = $true }
			Mock Get-Process {
				@([PSCustomObject]@{ ProcessName = 'WindowsTerminal'; Id = 4567 })
			} -ParameterFilter { $Name -eq 'WindowsTerminal' }
			Mock Start-Process { }

			Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup -ClosedTabs @('TabA', 'TabB') -StartingTitle 'CurrentTab' -OriginalHostTitle 'OriginalTitle'

			Should -Invoke Start-Process -Times 1 -Exactly
			$script:exitInvoked | Should -BeTrue
		}

		It "invokes exit seam even when no WindowsTerminal process is found" {
			$script:exitInvoked = $false
			Mock Invoke-TerminateWindowsTerminalTabsExit { $script:exitInvoked = $true }
			Mock Get-Process { @() } -ParameterFilter { $Name -eq 'WindowsTerminal' }
			Mock Start-Process { }

			Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup -ClosedTabs @('TabA') -StartingTitle 'CurrentTab' -OriginalHostTitle 'OriginalTitle'

			Should -Invoke Start-Process -Times 0
			$script:exitInvoked | Should -BeTrue
		}

		It "waits before exiting when CloseWaitSeconds is specified" {
			$script:exitInvoked = $false
			Mock Invoke-TerminateWindowsTerminalTabsExit { $script:exitInvoked = $true }
			Mock Get-Process { @() } -ParameterFilter { $Name -eq 'WindowsTerminal' }
			Mock Start-Process { }

			Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup -ClosedTabs @('TabA') -StartingTitle 'CurrentTab' -OriginalHostTitle 'OriginalTitle' -CloseWaitSeconds 5

			Should -Invoke Start-Sleep -Times 1 -ParameterFilter { $Seconds -eq 5 }
			$script:exitInvoked | Should -BeTrue
		}
	}
}
