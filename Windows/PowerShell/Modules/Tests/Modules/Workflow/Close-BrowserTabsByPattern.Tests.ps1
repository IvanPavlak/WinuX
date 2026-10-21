#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Close-BrowserTabsByPattern.ps1"

	# Stub dependent functions
	function Get-WindowHandle { param($ProcessName) $null }
	function Close-Window { param([IntPtr[]]$Handle) 0 }
	# Window and Helper module seams, stubbed so they can be mocked without loading those modules.
	function Confirm-WindowForeground { param([IntPtr]$WindowHandle, [int]$BaseSettleMs, [int]$MaxAttempts) $false }
	function Clear-WindowCache { }
	function Wait-Until { param([scriptblock]$Condition, [int]$TimeoutMs, [int]$PollIntervalMs) $true }
}

Describe "Close-BrowserTabsByPattern" {
	BeforeEach {
		Mock Write-Host { }
		Mock Start-Sleep { }
		Mock Add-Type { }
	}

	Context "When no browser windows are found" {
		It "Should return 0" {
			Mock Get-WindowHandle { $null }

			$result = Close-BrowserTabsByPattern -ProcessName "chrome" -TitlePatterns @("(?i)swagger")

			$result | Should -Be 0
		}
	}

	Context "When browser windows exist with matching titles" {
		It "never closes a whole window whose title matches" {
			# The title is the active tab's: closing the window took every other tab with it.
			$mockWindow = [PSCustomObject]@{
				Title     = "Swagger UI - Chrome"
				Handle    = [IntPtr]::new(12345)
				ProcessId = 100
			}
			Mock Get-WindowHandle { $mockWindow }
			Mock Clear-WindowCache { }
			Mock Close-Window { 1 }
			Mock Confirm-WindowForeground { $false }

			{ Close-BrowserTabsByPattern -ProcessName "chrome" -TitlePatterns @("(?i)swagger") } | Should -Not -Throw

			Should -Invoke Close-Window -Times 0
			Should -Invoke Confirm-WindowForeground -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]12345 }
		}
	}

	Context "Keystrokes only ever go to the browser window" {
		BeforeEach {
			Mock Clear-WindowCache { }
			Mock Wait-Until { $true }
			Mock Close-Window { 1 }
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Title = "Problem loading page - Firefox"; Handle = [IntPtr]1; ProcessId = 100 }
					[PSCustomObject]@{ Title = "Search - Firefox"; Handle = [IntPtr]2; ProcessId = 100 }
				)
			}
		}

		It "leaves a window's tabs alone when it cannot be confirmed in the foreground" {
			# Unconfirmed focus means the keystroke would land elsewhere - in the terminal this runs
			# in, where Ctrl+W closes the calling tab. Mocked to fail, so no real key is ever sent.
			Mock Confirm-WindowForeground { $false }

			$result = Close-BrowserTabsByPattern -ProcessName "firefox" -TitlePatterns @("(?i)problem loading page", "(?i)MyProject")

			$result | Should -Be 0
			Should -Invoke Close-Window -Times 0
			Should -Invoke Confirm-WindowForeground -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]1 }
			Should -Invoke Confirm-WindowForeground -Times 1 -Exactly -ParameterFilter { $WindowHandle -eq [IntPtr]2 }
			Should -Invoke Wait-Until -Times 0
		}

		It "reads the tab title fresh, from the window being processed" {
			Mock Confirm-WindowForeground { $false }

			Close-BrowserTabsByPattern -ProcessName "firefox" -TitlePatterns @("(?i)MyProject") | Out-Null

			Should -Invoke Clear-WindowCache -Times 2 -Exactly
		}
	}

	Context "Parameter validation" {
		It "Should require ProcessName parameter" {
			$cmd = Get-Command Close-BrowserTabsByPattern
			$param = $cmd.Parameters['ProcessName']
			$mandatoryAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
			$mandatoryAttr.Mandatory | Should -BeTrue
		}

		It "Should require TitlePatterns parameter" {
			$cmd = Get-Command Close-BrowserTabsByPattern
			$param = $cmd.Parameters['TitlePatterns']
			$mandatoryAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
			$mandatoryAttr.Mandatory | Should -BeTrue
		}
	}
}
