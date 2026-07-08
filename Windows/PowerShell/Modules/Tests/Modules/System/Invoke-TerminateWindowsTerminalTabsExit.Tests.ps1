#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Invoke-TerminateWindowsTerminalTabsExit.ps1"
}

Describe "Invoke-TerminateWindowsTerminalTabsExit" {
	BeforeEach {
		$script:exitInvoked = $false
		$script:TerminateWindowsTerminalTabsExitAction = {
			$script:exitInvoked = $true
		}
	}

	AfterEach {
		$script:TerminateWindowsTerminalTabsExitAction = $null
	}

	It "invokes the configured exit seam action when present" {
		Invoke-TerminateWindowsTerminalTabsExit

		$script:exitInvoked | Should -BeTrue
	}
}
