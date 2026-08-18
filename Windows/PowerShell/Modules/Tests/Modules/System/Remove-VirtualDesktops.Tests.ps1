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

	# Captured before any mock exists: invoking the CommandInfo directly executes the genuine
	# cmdlet without name resolution, so a Get-Command mock body can delegate to it without
	# re-entering itself. (A module-qualified call does NOT bypass the mock - it recurses.)
	$script:RealGetCommand = Get-Command -Name Get-Command -CommandType Cmdlet

	# VirtualDesktop cmdlets come from an optional external module absent on CI runners.
	# Stub the ones these tests mock so Mock can attach (no-op where the real module exists).
	if (-not (Get-Command Get-DesktopCount -ErrorAction SilentlyContinue)) {
		function Get-DesktopCount { [CmdletBinding()] param() }
		function Get-DesktopList { [CmdletBinding()] param() }
		function Remove-Desktop { [CmdletBinding()] param($Desktop) }
		function Get-DesktopFromWindow { [CmdletBinding()] param($Hwnd) }
		function Get-DesktopIndex { [CmdletBinding()] param([Parameter(Position = 0)]$Desktop) }
	}
}

Describe "Remove-VirtualDesktops" {
	BeforeEach {
		$script:desktopCountCalls = 0
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

	Context "Index mode (remove named desktops outright)" {
		BeforeEach {
			# Five desktops, and the count follows the removals so the guards below are exercised
			# against a shrinking set rather than a frozen number.
			$script:currentDesktopCount = 5
			Mock Get-DesktopCount { $script:currentDesktopCount }
			Mock Remove-Desktop { $script:currentDesktopCount-- }
		}

		It "removes exactly the desktops named" {
			Remove-VirtualDesktops -Index 3, 4

			Should -Invoke Remove-Desktop -Times 2 -Exactly
			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 3 }
			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 4 }
		}

		It "removes the highest index first so the remaining targets do not shift" {
			$script:removalOrder = @()
			Mock Remove-Desktop { $script:removalOrder += $Desktop; $script:currentDesktopCount-- }

			Remove-VirtualDesktops -Index 1, 3, 2

			$script:removalOrder | Should -Be @(3, 2, 1)
		}

		It "removes desktop 0, which is a falsy index" {
			# A truthiness check anywhere on this path would silently spare the desktop a plain
			# workspace lands on.
			Remove-VirtualDesktops -Index 0

			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 0 }
		}

		It "de-duplicates repeated indexes" {
			Remove-VirtualDesktops -Index 3, 3, 3

			Should -Invoke Remove-Desktop -Times 1 -Exactly
		}

		It "skips an index that no longer exists" {
			$script:currentDesktopCount = 2

			Remove-VirtualDesktops -Index 7

			Should -Invoke Remove-Desktop -Times 0
		}

		It "always keeps the last desktop" {
			$script:currentDesktopCount = 1

			Remove-VirtualDesktops -Index 0

			Should -Invoke Remove-Desktop -Times 0
		}

		It "stops once only one desktop is left, even with more indexes to go" {
			$script:currentDesktopCount = 2

			Remove-VirtualDesktops -Index 0, 1

			Should -Invoke Remove-Desktop -Times 1 -Exactly
		}

		It "ignores negative indexes" {
			Remove-VirtualDesktops -Index -1, 3

			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 3 }
		}

		It "returns nothing on success, exactly as the other two modes do" {
			# The mode used to hand back the indexes it removed, for a caller that re-mapped stored
			# desktop indexes. No such caller exists - Close-Workspace resolves desktops live - so the
			# return value went, and with it a second output type on this function.
			$result = Remove-VirtualDesktops -Index 3

			$result | Should -BeNullOrEmpty
		}

		It "takes precedence over -EmptyOnly" {
			Mock Get-WindowHandle { @() }

			Remove-VirtualDesktops -EmptyOnly -Index 3

			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 3 }
		}

		It "removes nothing when -Index is supplied but empty" {
			# Load-bearing: keying the mode on the RESOLVED count instead of on -Index being supplied
			# would fall through to the default mode here, silently turning "remove these desktops"
			# into "remove every desktop".
			Remove-VirtualDesktops -Index @()

			Should -Invoke Remove-Desktop -Times 0
		}

		It "removes nothing when every index given is unusable" {
			Remove-VirtualDesktops -Index -1, -2

			Should -Invoke Remove-Desktop -Times 0
		}

		It "reports a failure as false rather than throwing" {
			Mock Remove-Desktop { throw 'The RPC server is unavailable. (0x800706BA)' }

			$result = Remove-VirtualDesktops -Index 3

			$result | Should -Be $false
		}
	}

	Context "Default mode (remove all except desktop 0)" {
		It "returns false when virtual desktop cmdlets are unavailable" {
			Mock Get-DesktopCount { throw "The term 'Get-DesktopCount' is not recognized as a name of a cmdlet" }
			Mock Remove-Desktop { }

			$result = Remove-VirtualDesktops

			$result | Should -Be $false
			Should -Invoke Remove-Desktop -Times 0
		}

		It "removes desktops from right to left until a single desktop remains" {
			Mock Get-DesktopCount {
				$script:desktopCountCalls++
				switch ($script:desktopCountCalls) {
					1 { 3 }
					2 { 2 }
					default { 1 }
				}
			}
			Mock Remove-Desktop { }

			Remove-VirtualDesktops

			Should -Invoke Remove-Desktop -Times 2 -Exactly
			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 2 }
			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 1 }
		}

		It "reads the desktop count instead of the more expensive desktop list" {
			Mock Get-DesktopCount { 1 }
			Mock Get-DesktopList { @(0) }
			Mock Remove-Desktop { }

			Remove-VirtualDesktops

			Should -Invoke Get-DesktopCount -Times 1 -Exactly
			Should -Invoke Get-DesktopList -Times 0
		}

		It "lists the removed desktops in the normal-mode summary" {
			Mock Get-DesktopCount {
				$script:desktopCountCalls++
				switch ($script:desktopCountCalls) {
					1 { 3 }
					2 { 2 }
					default { 1 }
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
			Mock Get-DesktopCount { 2 }
			Mock Remove-Desktop { throw "desktop removal failed" }

			$result = Remove-VirtualDesktops

			$result | Should -Be $false
		}

		It "requests a live RPC probe before desktop cleanup" {
			Mock Get-DesktopCount { 1 }
			Mock Remove-Desktop { }

			Remove-VirtualDesktops

			Should -Invoke Get-RpcRetryPolicy -Times 1 -Exactly -ParameterFilter {
				$OperationLabel -eq "desktop cleanup" -and $Probe -and $MaxAttempts -eq 5 -and $InitialDelayMs -eq 250
			}
		}

		It "resets VirtualDesktop state when an RPC-unavailable call is retried" {
			Mock Get-DesktopCount {
				$script:desktopCountCalls++
				if ($script:desktopCountCalls -eq 1) {
					throw "The RPC server is unavailable. (0x800706BA)"
				}
				1
			}
			Mock Remove-Desktop { }

			Remove-VirtualDesktops

			$script:desktopCountCalls | Should -Be 2
			Should -Invoke Reset-VirtualDesktopState -Times 1 -Exactly
		}
	}

	Context "EmptyOnly mode" {
		BeforeEach {
			# Pester 6 throws when a mocked command is called and no parameter filter matches;
			# v5 fell through to the real command. This default mock restores the v5 fallthrough
			# by delegating to the CommandInfo captured in BeforeAll.
			Mock Get-Command { & $script:RealGetCommand @PesterBoundParameters }
		}

		It "does nothing when only one desktop exists" {
			Mock Get-DesktopCount { 1 }
			Mock Remove-Desktop { }

			Remove-VirtualDesktops -EmptyOnly

			Should -Invoke Remove-Desktop -Times 0
		}

		It "removes empty desktops and keeps occupied desktops" {
			Mock Get-DesktopCount {
				$script:desktopCountCalls++
				if ($script:desktopCountCalls -eq 1) { 4 } else { 3 }
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

		It "skips windows the desktop manager cannot place without retrying them" {
			# A shell window such as "Windows Input Experience" answers TYPE_E_ELEMENTNOTFOUND
			# forever; retrying it used to burn the whole backoff ladder on every run.
			Mock Get-DesktopCount {
				$script:desktopCountCalls++
				if ($script:desktopCountCalls -eq 1) { 3 } else { 2 }
			}
			Mock Get-Command {
				[PSCustomObject]@{ Name = 'Get-WindowHandle' }
			} -ParameterFilter { $Name -eq 'Get-WindowHandle' }
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]11 },
					[PSCustomObject]@{ Handle = [IntPtr]99 }
				)
			}
			Mock Get-DesktopFromWindow {
				if ($Hwnd -eq [IntPtr]99) { throw "Element not found. (0x8002802B (TYPE_E_ELEMENTNOTFOUND))" }
				'desktop-1'
			}
			Mock Get-DesktopIndex { 1 }
			Mock Remove-Desktop { }

			Remove-VirtualDesktops -EmptyOnly

			# One call per window - no backoff ladder, no rescan.
			Should -Invoke Get-DesktopFromWindow -Times 2 -Exactly
			Should -Invoke Start-Sleep -Times 0
			Should -Invoke Remove-Desktop -Times 2 -Exactly
			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 2 }
			Should -Invoke Remove-Desktop -Times 1 -Exactly -ParameterFilter { $Desktop -eq 0 }
		}

		It "resolves each distinct desktop once no matter how many windows sit on it" {
			Mock Get-DesktopCount {
				$script:desktopCountCalls++
				if ($script:desktopCountCalls -eq 1) { 3 } else { 2 }
			}
			Mock Get-Command {
				[PSCustomObject]@{ Name = 'Get-WindowHandle' }
			} -ParameterFilter { $Name -eq 'Get-WindowHandle' }
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]11 },
					[PSCustomObject]@{ Handle = [IntPtr]22 },
					[PSCustomObject]@{ Handle = [IntPtr]33 }
				)
			}
			Mock Get-DesktopFromWindow { 'desktop-1' }
			Mock Get-DesktopIndex { 1 }
			Mock Remove-Desktop { }

			Remove-VirtualDesktops -EmptyOnly

			Should -Invoke Get-DesktopFromWindow -Times 3 -Exactly
			Should -Invoke Get-DesktopIndex -Times 1 -Exactly
		}

		It "stops scanning once every desktop is known to be occupied" {
			Mock Get-DesktopCount { 2 }
			Mock Get-Command {
				[PSCustomObject]@{ Name = 'Get-WindowHandle' }
			} -ParameterFilter { $Name -eq 'Get-WindowHandle' }
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]11 },
					[PSCustomObject]@{ Handle = [IntPtr]22 },
					[PSCustomObject]@{ Handle = [IntPtr]33 }
				)
			}
			Mock Get-DesktopFromWindow {
				if ($Hwnd -eq [IntPtr]11) { 'desktop-0' } else { 'desktop-1' }
			}
			Mock Get-DesktopIndex {
				if ($Desktop -eq 'desktop-0') { 0 } else { 1 }
			}
			Mock Remove-Desktop { }

			Remove-VirtualDesktops -EmptyOnly

			# Both desktops are occupied after the first two windows - the third is never looked up.
			Should -Invoke Get-DesktopFromWindow -Times 2 -Exactly
			Should -Invoke Remove-Desktop -Times 0
		}

		It "aborts without removing anything when RPC stays unavailable during the scan" {
			Mock Get-DesktopCount { 3 }
			Mock Get-Command {
				[PSCustomObject]@{ Name = 'Get-WindowHandle' }
			} -ParameterFilter { $Name -eq 'Get-WindowHandle' }
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Handle = [IntPtr]11 })
			}
			Mock Get-DesktopFromWindow { throw "The RPC server is unavailable. (0x800706BA)" }
			Mock Remove-Desktop { }

			$result = Remove-VirtualDesktops -EmptyOnly

			$result | Should -Be $false
			Should -Invoke Remove-Desktop -Times 0
			# The whole scan is retried (with a state reset between attempts), not each window.
			Should -Invoke Reset-VirtualDesktopState -Times 2 -Exactly
		}

		It "falls back to process MainWindowHandle enumeration when Get-WindowHandle is unavailable" {
			Mock Get-DesktopCount {
				$script:desktopCountCalls++
				if ($script:desktopCountCalls -eq 1) { 3 } else { 2 }
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
