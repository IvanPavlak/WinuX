#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Initialize-Win32BrowserHelperType.ps1"
	. "$FunctionsPath\Get-BrowserWindowsByTarget.ps1"
	. "$FunctionsPath\Close-BrowserWindows.ps1"
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
		Mock Initialize-Win32BrowserHelperType { }
		Mock Get-BrowserWindowsByTarget { @() }
		Mock Close-BrowserWindows {
			param($WindowsToClose)
			$script:closedWindowTitles += @($WindowsToClose | ForEach-Object { $_.Title })
		}
	}

	It "returns cleanly when browser configuration is missing" {
		$script:Configuration = @{}

		Terminate-AllBrowserProcesses

		Should -Invoke Get-Process -Times 0
	}

	It "returns cleanly when no configured browser processes are running" {
		$script:Configuration = @{
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
		$script:Configuration = @{
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
		$script:Configuration = @{
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
}
