#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Reset-VirtualDesktopState.ps1"

	# Sibling helpers stubbed so they can be mocked.
	function Import-VirtualDesktopModule { param([switch]$Silent) }
	function Reset-VirtualDesktopComProxy { }
	function Test-VirtualDesktopComHealth { param([int]$TimeoutMs) }
	if (-not (Get-Command Write-LogDebug -ErrorAction SilentlyContinue)) {
		function Write-LogDebug { param($Message, [string]$Style, [switch]$NoLeadingNewline) }
	}
}

Describe "Reset-VirtualDesktopState" {
	BeforeEach {
		$script:VirtualDesktopState = @{
			Checked   = $true
			Available = $true
			Loaded    = $true
		}
		Mock Remove-Module { }
		Mock Write-LogDebug { }
		Mock Reset-VirtualDesktopComProxy { $true }
		Mock Test-VirtualDesktopComHealth { [PSCustomObject]@{ Healthy = $true; TimedOut = $false; Error = $null } }
	}

	It "removes the VirtualDesktop module and re-imports it" {
		Mock Import-VirtualDesktopModule { $true }

		$null = Reset-VirtualDesktopState

		Should -Invoke Remove-Module -Times 1 -ParameterFilter { $Name -eq 'VirtualDesktop' }
		Should -Invoke Import-VirtualDesktopModule -Times 1
	}

	It "reconnects the compiled COM proxies as part of the reset" {
		Mock Import-VirtualDesktopModule { $true }

		$null = Reset-VirtualDesktopState

		# This is the layer that actually repairs a stale session; re-importing the
		# module alone can never refresh the static COM fields.
		Should -Invoke Reset-VirtualDesktopComProxy -Times 1
	}

	It "invalidates the lazy-load cache before re-importing" {
		Mock Import-VirtualDesktopModule { $true }

		$null = Reset-VirtualDesktopState

		# After a reset the cached availability flags must be cleared so the next
		# Import-VirtualDesktopModule call re-establishes a fresh session.
		$script:VirtualDesktopState.Checked | Should -BeFalse
		$script:VirtualDesktopState.Available | Should -BeFalse
		$script:VirtualDesktopState.Loaded | Should -BeFalse
	}

	It "returns true when reconnect, re-import, and verification all succeed" {
		Mock Import-VirtualDesktopModule { $true }

		Reset-VirtualDesktopState | Should -BeTrue
	}

	It "returns false when the module fails to re-import" {
		Mock Import-VirtualDesktopModule { $false }

		Reset-VirtualDesktopState | Should -BeFalse
	}

	It "returns false when the COM proxy reconnect fails" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Reset-VirtualDesktopComProxy { $false }

		Reset-VirtualDesktopState | Should -BeFalse
	}

	It "returns false when the post-reset roundtrip still reports an unhealthy session" {
		Mock Import-VirtualDesktopModule { $true }
		Mock Test-VirtualDesktopComHealth {
			[PSCustomObject]@{ Healthy = $false; TimedOut = $false; Error = 'The RPC server is unavailable. (0x800706BA)' }
		}

		# A reset that leaves the session broken must not report success.
		Reset-VirtualDesktopState | Should -BeFalse
	}

	It "still resets state when Remove-Module throws" {
		Mock Remove-Module { throw "module locked" }
		Mock Import-VirtualDesktopModule { $true }

		{ Reset-VirtualDesktopState } | Should -Not -Throw
		$script:VirtualDesktopState.Loaded | Should -BeFalse
	}
}
