#Requires -Modules Pester

BeforeAll {
	. (Join-Path (Get-RepositoryPath).Modules "Tests\Modules\Support\Reset-WindowModuleState.ps1")
	Reset-WindowModuleState
	$script:Window = Get-Module -Name Window | Select-Object -First 1
}

Describe "Reset-WindowModuleState (test support)" {
	It "puts the import-time state back after a test changed it" {
		$baseline = & $script:Window { $script:WindowModuleDelays.Clone() }

		& $script:Window {
			$script:WindowModuleDelays.CursorSettleMs = 999
			$script:MonitorCache.Monitors = @('stale monitor')
			$script:WorkspaceRerunCommand = 'Open-Workspace Stale'
		}
		Reset-WindowModuleState

		$after = & $script:Window { [pscustomobject]@{ Delays = $script:WindowModuleDelays; Monitors = $script:MonitorCache.Monitors; Rerun = $script:WorkspaceRerunCommand } }
		$after.Delays.CursorSettleMs | Should -Be $baseline.CursorSettleMs
		$after.Delays.Count | Should -Be $baseline.Count
		$after.Monitors | Should -BeNullOrEmpty
		$after.Rerun | Should -BeNullOrEmpty
	}

	It "removes state the functions created after import, as a fresh import would" {
		& $script:Window {
			$script:PositionedWindowHandles = @{ 100 = $true }
			$script:LastSnapAllWindowsResult = 'stale'
		}
		Reset-WindowModuleState

		& $script:Window { Test-Path -LiteralPath 'Variable:script:PositionedWindowHandles' } | Should -BeFalse
		& $script:Window { Test-Path -LiteralPath 'Variable:script:LastSnapAllWindowsResult' } | Should -BeFalse
	}

	It "does not reload the module's functions" {
		$before = (Get-Command -Name Center-Text -Module Window).ScriptBlock
		Reset-WindowModuleState
		[object]::ReferenceEquals($before, (Get-Command -Name Center-Text -Module Window).ScriptBlock) | Should -BeTrue
		@(Get-Module -Name Window).Count | Should -Be 1
	}
}
