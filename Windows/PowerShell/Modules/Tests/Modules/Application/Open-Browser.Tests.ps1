#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-Browser.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Open-Browser" {
	BeforeEach {
		$global:Configuration = @{
			Universal     = @{
				DefaultBrowser = 'Chrome'
				Browsers       = @{
					Chrome = @{
						Exe          = 'C:\\Tools\\chrome.exe'
						PrivateArg   = '--incognito'
						NewWindowArg = '--new-window'
					}
				}
			}
			BrowserGroups = @(
				@{
					Work = @(
						'https://github.com'
					)
				}
			)
		}

		Mock Write-Host { }
		Mock Resolve-Selection {
			@(
				[PSCustomObject]@{
					PathNames = @('Work')
					IsParent  = $false
				}
			)
		}
		Mock Get-WindowHandle { @() }
		Mock Test-BrowserGroupAlreadyOpen { $false }
		Mock Start-Process { }
	}

	It "resolves configured group and opens URL with browser new-window argument" {
		Open-Browser -Groups Work -Browser Chrome

		Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter {
			$GroupsConfig.Count -eq 1 -and $InputObject -contains 'Work'
		}
		Should -Invoke Test-BrowserGroupAlreadyOpen -Times 1 -Exactly
		Should -Invoke Start-Process -Times 1 -Exactly
		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
			$ArgumentList -contains '--new-window' -and $ArgumentList -contains 'https://github.com'
		}
	}

	It "skips launching a group when Test-BrowserGroupAlreadyOpen reports it is already open" {
		Mock Test-BrowserGroupAlreadyOpen { $true }

		Open-Browser -Groups Work -Browser Chrome

		Should -Invoke Test-BrowserGroupAlreadyOpen -Times 1 -Exactly
		Should -Invoke Start-Process -Times 0
	}

	It "opens only missing instances in group Instances mode" {
		Mock Test-BrowserGroupAlreadyOpen { 1 }

		Open-Browser -Groups Work -Browser Chrome -Instances 3

		Should -Invoke Test-BrowserGroupAlreadyOpen -Times 1 -Exactly -ParameterFilter {
			$ReturnCount -eq $true
		}
		Should -Invoke Start-Process -Times 2 -Exactly -ParameterFilter {
			$ArgumentList[0] -eq '--new-window' -and $ArgumentList[1] -eq 'https://github.com'
		}
	}

	It "bypasses already-open checks when Override is set" {
		Mock Test-BrowserGroupAlreadyOpen { $true }

		Open-Browser -Groups Work -Browser Chrome -Override

		Should -Invoke Test-BrowserGroupAlreadyOpen -Times 0
		Should -Invoke Start-Process -Times 1 -Exactly
	}
}
