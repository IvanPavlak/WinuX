#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Invoke-RerunLastCommandExit.ps1"
	. "$FunctionsPath\ReRun-LastCommand.ps1"

	# The graceful close goes through the Window module's Close-Window seam. Stubbed so Mock can
	# attach without the Window module and so no WM_CLOSE is ever posted from a test.
	function Close-Window { param([IntPtr[]]$Handle) $Handle.Count }
}

Describe "ReRun-LastCommand" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
	}

	It "returns when PSReadLine history path cannot be accessed" {
		Mock Get-PSReadLineOption { throw "Unavailable" }

		{ ReRun-LastCommand -AutoAccept } | Should -Not -Throw
		Should -Invoke Write-LogWarning -Times 1
		Should -Invoke Write-LogError -Times 1
	}

	It "returns when history file does not exist" {
		Mock Get-PSReadLineOption { [PSCustomObject]@{ HistorySavePath = "C:\\missing_history.txt" } }
		Mock Test-Path { $false }

		{ ReRun-LastCommand -AutoAccept } | Should -Not -Throw
		Should -Invoke Write-LogWarning -Times 1
		Should -Invoke Write-LogError -Times 1
	}

	Context "Closing the original window" {
		BeforeEach {
			Mock Write-LogSuccess { }
			Mock Write-LogDebug { }
			Mock Start-Sleep { }
			# No Windows Terminal process => the AppActivate/focus block is skipped entirely.
			Mock Get-Process { $null }
			Mock Terminate-WindowsTerminalTabs { }
			Mock Open-Terminal { }
			Mock Reset-KeyboardModifiers { @() }
			Mock Invoke-RerunLastCommandExit { }

			Mock Close-Window { 1 }
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Title = "Original"; Handle = [IntPtr]424243 })
			}
		}

		It "posts WM_CLOSE to the captured original window handle through Close-Window" {
			ReRun-LastCommand -Command "Get-ChildItem"

			Should -Invoke Close-Window -Times 1 -Exactly -ParameterFilter {
				@($Handle)[0] -eq [IntPtr]424243
			}
			Should -Invoke Write-LogDebug -Times 1 -Exactly -ParameterFilter {
				$Message -match 'WM_CLOSE => \[424243\]'
			}
			Should -Invoke Invoke-RerunLastCommandExit -Times 1 -Exactly
		}

		It "never synthesizes a keyboard shortcut to close the window" {
			# The defect this guards: Ctrl+Shift+W closed the window hosting this very process,
			# so the process died mid-injection - before the Ctrl/Shift key-ups were sent - and
			# both modifiers stayed logically held for the rest of the desktop session.
			$definition = (Get-Command ReRun-LastCommand).Definition

			$definition | Should -Not -Match 'SendKeys'
			$definition | Should -Not -Match '"\^\+w"'
		}

		It "closes without depending on foreground state" {
			ReRun-LastCommand -Command "Get-ChildItem"

			# The close is the deterministic Close-Window seam only - no private user32 type and no
			# focus API in this function, so the close cannot regress into a focus-then-type sequence.
			$definition = (Get-Command ReRun-LastCommand).Definition

			$definition | Should -Not -Match 'Add-Type @"'
			$definition | Should -Not -Match 'DllImport'
			$definition | Should -Not -Match 'SetForegroundWindow'
			Should -Invoke Close-Window -Times 1 -Exactly
		}

		It "heals stuck modifiers as the last act before the exit seam" {
			$script:callOrder = [System.Collections.Generic.List[string]]::new()
			Mock Reset-KeyboardModifiers { $script:callOrder.Add('reset'); @() }
			Mock Terminate-WindowsTerminalTabs { $script:callOrder.Add('terminate') }
			Mock Open-Terminal { $script:callOrder.Add('open') }
			Mock Invoke-RerunLastCommandExit { $script:callOrder.Add('exit') }

			ReRun-LastCommand -Command "Get-ChildItem"

			# [Environment]::Exit skips every finally block, so the heal has to be the last
			# thing that runs - after the tab-close passes that synthesize Ctrl+Tab/Ctrl+W.
			$script:callOrder -join ' -> ' | Should -Be 'reset -> terminate -> open -> reset -> exit'
		}

		It "skips the close but still opens the fresh shell when no original window was found" {
			Mock Get-WindowHandle { @() }

			{ ReRun-LastCommand -Command "Get-ChildItem" } | Should -Not -Throw

			Should -Invoke Open-Terminal -Times 1 -Exactly
			Should -Invoke Write-LogDebug -Times 0 -ParameterFilter { $Message -match 'WM_CLOSE' }
			Should -Invoke Invoke-RerunLastCommandExit -Times 1 -Exactly
		}
	}
}
