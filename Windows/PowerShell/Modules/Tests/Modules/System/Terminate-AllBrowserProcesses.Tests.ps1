#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Get-BrowserTitlePattern.ps1"
	. "$FunctionsPath\Get-BrowserWindowsByTarget.ps1"
	. "$FunctionsPath\Close-BrowserWindows.ps1"
	. "$FunctionsPath\Wait-BrowserWindowsClosed.ps1"
	. "$FunctionsPath\Terminate-AllBrowserProcesses.ps1"

	function Test-WindowTitleMatch {
		param(
			[string]$WindowTitle,
			[string[]]$Patterns
		)
		$false
	}
}

Describe "Terminate-AllBrowserProcesses" {
	BeforeEach {
		$script:closedWindowTitles = @()

		Mock Write-Host { }
		Mock Add-Type { }
		Mock Get-Process { $null }
		Mock Test-WindowTitleMatch { $false }
		Mock Get-BrowserWindowsByTarget { @() }
		Mock Close-BrowserWindows {
			param($WindowsToClose)
			$script:closedWindowTitles += @($WindowsToClose | ForEach-Object { $_.Title })
		}
		# By default every posted WM_CLOSE takes effect: nothing is left standing to wait for.
		Mock Wait-BrowserWindowsClosed { @() }
		Mock Write-LogWarning { }
		Mock Write-LogList { }
		Mock Write-LogSuccess { }
	}

	It "returns cleanly when browser configuration is missing" {
		$global:Configuration = @{}

		Terminate-AllBrowserProcesses

		Should -Invoke Get-Process -Times 0
	}

	It "returns cleanly when no configured browser processes are running" {
		$global:Configuration = @{
			Universal = @{
				Browsers = @{
					Firefox = @{ Exe = 'firefox.exe' }
					Chrome  = @{ Exe = 'chrome.exe' }
				}
			}
		}
		Mock Get-Process { @() }

		Terminate-AllBrowserProcesses

		Should -Invoke Get-Process -Times 2 -Exactly
	}

	It "skips unknown browser keys that have no title pattern mapping" {
		$global:Configuration = @{
			Universal = @{
				Browsers = @{
					CustomBrowser = @{ Exe = 'custom.exe' }
				}
			}
		}

		Terminate-AllBrowserProcesses

		Should -Invoke Get-Process -Times 0
	}

	It "applies exclusion patterns per window and closes only non-excluded browser windows" {
		$global:Configuration = @{
			Universal = @{
				Browsers = @{
					Chrome = @{ Exe = 'chrome.exe' }
				}
			}
		}

		Mock Get-Process {
			@([PSCustomObject]@{ Id = 4444 })
		} -ParameterFilter { $Name -eq 'chrome' }

		Mock Get-BrowserWindowsByTarget {
			@(
				[PSCustomObject]@{ Handle = [IntPtr]11; Title = 'YouTube - Google Chrome' },
				[PSCustomObject]@{ Handle = [IntPtr]22; Title = 'Work Docs - Google Chrome' }
			)
		}

		Mock Test-WindowTitleMatch {
			param($WindowTitle, $Patterns)
			$WindowTitle -like '*YouTube*'
		}

		Terminate-AllBrowserProcesses -Exclude '*YouTube*'

		Should -Invoke Test-WindowTitleMatch -Times 2 -Exactly
		Should -Invoke Close-BrowserWindows -Times 1 -Exactly
		$script:closedWindowTitles.Count | Should -Be 1
		$script:closedWindowTitles[0] | Should -Be 'Work Docs - Google Chrome'
	}

	Context "waiting for the windows to close" {
		BeforeEach {
			$global:Configuration = @{
				Universal = @{
					Browsers = @{
						Firefox = @{ Exe = 'firefox.exe' }
					}
				}
			}
			Mock Get-Process {
				@([PSCustomObject]@{ Id = 5555 })
			} -ParameterFilter { $Name -eq 'firefox' }
			Mock Get-BrowserWindowsByTarget {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]31; Title = 'Mail - Mozilla Firefox'; ProcessId = 5555; MatchesPattern = $true },
					[PSCustomObject]@{ Handle = [IntPtr]32; Title = 'Picture-in-Picture'; ProcessId = 5555; MatchesPattern = $false }
				)
			}
		}

		It "closes windows without the brand suffix too, and waits for every posted close" {
			Terminate-AllBrowserProcesses

			$script:closedWindowTitles | Should -Contain 'Picture-in-Picture'
			Should -Invoke Wait-BrowserWindowsClosed -Times 1 -Exactly -ParameterFilter { @($Windows).Count -eq 2 }
			Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -match 'successfully' }
		}

		It "posts WM_CLOSE again to a window that was still open after the first wait" {
			$script:waits = 0
			Mock Wait-BrowserWindowsClosed {
				$script:waits++
				if ($script:waits -eq 1) { @($Windows | Where-Object { $_.Handle -eq [IntPtr]31 }) } else { @() }
			}

			Terminate-AllBrowserProcesses

			# First round: both windows. Retry round: only the survivor.
			Should -Invoke Close-BrowserWindows -Times 2 -Exactly
			Should -Invoke Close-BrowserWindows -Times 1 -Exactly -ParameterFilter {
				@($WindowsToClose).Count -eq 1 -and $WindowsToClose[0].Handle -eq [IntPtr]31
			}
			Should -Invoke Write-LogWarning -Times 0
			Should -Invoke Write-LogSuccess -Times 1 -ParameterFilter { $Message -match 'successfully' }
		}

		It "reports windows that survive both rounds instead of declaring success" {
			Mock Wait-BrowserWindowsClosed {
				@($Windows | Where-Object { $_.Handle -eq [IntPtr]31 })
			}

			Terminate-AllBrowserProcesses

			Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -match '1 browser window\(s\) did not close' }
			Should -Invoke Write-LogList -Times 1 -Exactly -ParameterFilter { @($Items) -contains 'Mail - Mozilla Firefox' }
			Should -Invoke Write-LogSuccess -Times 0
		}

		It "closes a window reachable through two targets sharing a process name only once" {
			$global:Configuration = @{
				Universal = @{
					Browsers = @{
						Firefox = @{ Exe = 'firefox.exe' }
						Tor     = @{ Exe = 'Tor Browser\firefox.exe' }
					}
				}
			}

			Terminate-AllBrowserProcesses

			# Both targets resolve to the same firefox PIDs and the same two windows.
			Should -Invoke Get-BrowserWindowsByTarget -Times 2 -Exactly
			$script:closedWindowTitles.Count | Should -Be 2
		}
	}
}
