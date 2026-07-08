#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Reset-VirtualDesktopState.ps1"

	# Import-VirtualDesktopModule is a sibling helper; stub it so it can be mocked.
	function Import-VirtualDesktopModule { param([switch]$Silent) }
}

Describe "Reset-VirtualDesktopState" {
	BeforeEach {
		$script:VirtualDesktopState = @{
			Checked   = $true
			Available = $true
			Loaded    = $true
		}
		Mock Remove-Module { }
	}

	It "removes the VirtualDesktop module and re-imports it" {
		Mock Import-VirtualDesktopModule { $true }

		$null = Reset-VirtualDesktopState

		Should -Invoke Remove-Module -Times 1 -ParameterFilter { $Name -eq 'VirtualDesktop' }
		Should -Invoke Import-VirtualDesktopModule -Times 1
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

	It "returns true when the module is ready after the reset" {
		Mock Import-VirtualDesktopModule { $true }

		Reset-VirtualDesktopState | Should -BeTrue
	}

	It "returns false when the module fails to re-import" {
		Mock Import-VirtualDesktopModule { $false }

		Reset-VirtualDesktopState | Should -BeFalse
	}

	It "still resets state when Remove-Module throws" {
		Mock Remove-Module { throw "module locked" }
		Mock Import-VirtualDesktopModule { $true }

		{ Reset-VirtualDesktopState } | Should -Not -Throw
		$script:VirtualDesktopState.Loaded | Should -BeFalse
	}
}
