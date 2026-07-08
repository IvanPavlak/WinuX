#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Window Module Delays Configuration" {
	Context "Get-WindowModuleDelays" {
		It "Should return delay configuration hashtable" {
			$delays = Get-WindowModuleDelays

			$delays | Should -BeOfType [hashtable]
			$delays.ContainsKey('CursorSettleMs') | Should -Be $true
			$delays.ContainsKey('FocusSettleMs') | Should -Be $true
			$delays.ContainsKey('KeyboardShortcutMs') | Should -Be $true
			$delays.ContainsKey('WindowRestoreMs') | Should -Be $true
			$delays.ContainsKey('WindowPositionMs') | Should -Be $true
			$delays.ContainsKey('VirtualDesktopMs') | Should -Be $true
		}

		It "Should have all delay values as positive integers" {
			$delays = Get-WindowModuleDelays

			foreach ($key in $delays.Keys) {
				$delays[$key] | Should -BeOfType [int]
				$delays[$key] | Should -BeGreaterOrEqual 0
			}
		}
	}

	Context "Set-WindowModuleDelays" {
		BeforeAll {
			# Store original delays
			$script:OriginalDelays = Get-WindowModuleDelays
		}

		AfterAll {
			# Restore original delays
			if ($script:OriginalDelays) {
				Set-WindowModuleDelays -Delays $script:OriginalDelays
			}
		}

		It "Should update delay configuration" {
			$newDelays = @{
				CursorSettleMs     = 10
				FocusSettleMs      = 10
				KeyboardShortcutMs = 10
				WindowRestoreMs    = 10
				WindowPositionMs   = 10
				VirtualDesktopMs   = 10
			}

			Set-WindowModuleDelays -Delays $newDelays

			$result = Get-WindowModuleDelays
			$result.CursorSettleMs | Should -Be 10
			$result.FocusSettleMs | Should -Be 10
		}
	}
}
