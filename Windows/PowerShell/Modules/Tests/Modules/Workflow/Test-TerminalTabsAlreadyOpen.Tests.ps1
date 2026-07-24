#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Test-TerminalTabsAlreadyOpen.ps1"

	# Module-private keystroke wrapper (defined alongside Open-ProjectTerminals) and the
	# Helper UIA reader - stub both so mocks can attach in this dot-sourced context and no
	# real keystrokes/UIA calls happen during tests.
	if (-not (Get-Command Send-TerminalKeys -ErrorAction SilentlyContinue)) {
		function Send-TerminalKeys { param([Parameter(Mandatory)][string]$Keys) }
	}
	if (-not (Get-Command Get-WindowsTerminalTabTitles -ErrorAction SilentlyContinue)) {
		function Get-WindowsTerminalTabTitles { param([IntPtr]$WindowHandle) $null }
	}
}

Describe "Test-TerminalTabsAlreadyOpen" {
	BeforeEach {
		Mock Write-Host { }
	}

	It "returns AllOpen false when Windows Terminal is not running" {
		Mock Get-Process { @() }

		$result = Test-TerminalTabsAlreadyOpen -ExpectedTabNames @("WinuX.Root") -ProjectName "WinuX"

		$result.AllOpen | Should -BeFalse
		$result.FoundTabs | Should -BeNullOrEmpty
	}

	It "returns AllOpen false when exception is thrown" {
		Mock Get-Process { throw "boom" }

		$result = Test-TerminalTabsAlreadyOpen -ExpectedTabNames @("WinuX.Root") -ProjectName "WinuX"

		$result.AllOpen | Should -BeFalse
		$result.FoundTabs | Should -BeNullOrEmpty
	}

	Context "UIA-first tab reading" {
		BeforeEach {
			Mock Get-Process { @([PSCustomObject]@{ ProcessName = 'WindowsTerminal'; Id = 4321 }) }
			Mock Add-Type { }
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Handle = [IntPtr]100; Title = 'WinuX.Root'; ProcessName = 'WindowsTerminal' })
			}
			Mock Start-Sleep { }
			Mock Send-TerminalKeys { }
		}

		It "finds tabs via UIA without focusing windows or sending keystrokes" {
			Mock Get-WindowsTerminalTabTitles { @('WinuX.Root', 'WinuX.DOCS', 'pwsh') }

			$result = Test-TerminalTabsAlreadyOpen -ExpectedTabNames @('WinuX.Root', 'WinuX.DOCS') -ProjectName 'WinuX'

			$result.AllOpen | Should -BeTrue
			$result.FoundTabs | Should -Contain 'WinuX.Root'
			$result.FoundTabs | Should -Contain 'WinuX.DOCS'
			# The whole point of the UIA path: no foreground stealing, no Ctrl+Tab typing.
			Should -Invoke Start-Sleep -Times 0
		}

		It "reports missing tabs from the UIA titles" {
			Mock Get-WindowsTerminalTabTitles { @('WinuX.Root') }

			$result = Test-TerminalTabsAlreadyOpen -ExpectedTabNames @('WinuX.Root', 'WinuX.DOCS') -ProjectName 'WinuX'

			$result.AllOpen | Should -BeFalse
			$result.FoundTabs | Should -Be @('WinuX.Root')
		}

		It "falls back to the legacy cycling pass when UIA cannot read the tabs" {
			Mock Get-WindowsTerminalTabTitles { $null }

			$result = Test-TerminalTabsAlreadyOpen -ExpectedTabNames @('WinuX.Root') -ProjectName 'WinuX'

			# The window title (active tab) matches in the legacy pass.
			$result.AllOpen | Should -BeTrue
			$result.FoundTabs | Should -Be @('WinuX.Root')
		}
	}
}
