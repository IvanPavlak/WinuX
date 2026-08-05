#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$ModuleRoot = (Get-RepositoryPath).Modules
	$AppFunctionsPath = Join-Path $ModuleRoot "Application\Functions"

	# The unconfigured-section guards warn through Confirm-ConfigValue (Helper);
	# dot-source it (and its Test-ConfigValue dependency) so the Write-LogWarning
	# mocks in these tests apply to the guard's warning.
	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"

	# Instance counting and the cold-start gate lean on these two.
	. "$ModuleRoot\System\Functions\Get-BrowserTitlePattern.ps1"
	. "$AppFunctionsPath\Wait-BrowserWindowReady.ps1"

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
		Mock Wait-BrowserWindowReady { $true }
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

	It "opens the full group instance count in alongside mode, ignoring already-open windows" {
		# An alongside layout refuses every window that existed before the workspace opened,
		# so counting those toward the target leaves that many zones unfillable.
		Mock Test-BrowserGroupAlreadyOpen { 1 }

		Open-Browser -Groups Work -Browser Chrome -Instances 3 -Alongside

		Should -Invoke Start-Process -Times 3 -Exactly -ParameterFilter {
			$ArgumentList[0] -eq '--new-window' -and $ArgumentList[1] -eq 'https://github.com'
		}
	}

	It "bypasses already-open checks when Override is set" {
		Mock Test-BrowserGroupAlreadyOpen { $true }

		Open-Browser -Groups Work -Browser Chrome -Override

		Should -Invoke Test-BrowserGroupAlreadyOpen -Times 0
		Should -Invoke Start-Process -Times 1 -Exactly
	}

	Context "NoMenu Instances mode" {
		It "opens each missing instance with the browser new-window argument" {
			# A bare launch only opens a window on some browsers (Brave routes it
			# into the existing session as a tab), so every instance launch must
			# carry NewWindowArg.
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Handle = [IntPtr]11; Title = 'New Tab - Google Chrome' })
			}

			Open-Browser -NoMenu -Browser Chrome -Instances 3

			Should -Invoke Start-Process -Times 2 -Exactly -ParameterFilter {
				$ArgumentList -contains '--new-window'
			}
		}

		It "waits for the first window before bursting the rest on a cold start" {
			Mock Get-WindowHandle { @() }

			Open-Browser -NoMenu -Browser Chrome -Instances 3

			Should -Invoke Start-Process -Times 3 -Exactly
			Should -Invoke Wait-BrowserWindowReady -Times 1 -Exactly
		}

		It "does not count another browser's windows that share the process name" {
			$global:Configuration.Universal.Browsers['Firefox'] = @{
				Exe          = 'C:\\Tools\\firefox.exe'
				PrivateArg   = '-private-window'
				NewWindowArg = '-new-window'
			}

			# Tor Browser runs as firefox.exe - its windows must not count as
			# existing Firefox instances.
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Handle = [IntPtr]11; Title = 'Connect to Tor - Tor Browser' })
			}

			Open-Browser -NoMenu -Browser Firefox -Instances 2

			Should -Invoke Start-Process -Times 2 -Exactly
		}

		It "opens nothing when the instance target is already met" {
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]11; Title = 'New Tab - Google Chrome' },
					[PSCustomObject]@{ Handle = [IntPtr]22; Title = 'Docs - Google Chrome' }
				)
			}
			Mock Write-LogWarning { }

			Open-Browser -NoMenu -Browser Chrome -Instances 2

			Should -Invoke Start-Process -Times 0
		}

		It "opens the full instance count in alongside mode even when the target is already met" {
			# The pre-existing windows belong to whichever workspace is already running - an
			# alongside layout is only allowed to place windows THIS open created, so all N
			# must be launched fresh or the layout is starved by exactly N-existing entries.
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Handle = [IntPtr]11; Title = 'New Tab - Google Chrome' },
					[PSCustomObject]@{ Handle = [IntPtr]22; Title = 'Docs - Google Chrome' }
				)
			}

			Open-Browser -NoMenu -Browser Chrome -Instances 2 -Alongside

			Should -Invoke Start-Process -Times 2 -Exactly -ParameterFilter {
				$ArgumentList -contains '--new-window'
			}
		}

		It "skips the cold-start gate in alongside mode when the browser is already warm" {
			# Pre-existing windows do not count toward the target, but they still prove the
			# browser is running - no need to wait for the first window before bursting.
			Mock Get-WindowHandle {
				@([PSCustomObject]@{ Handle = [IntPtr]11; Title = 'New Tab - Google Chrome' })
			}

			Open-Browser -NoMenu -Browser Chrome -Instances 3 -Alongside

			Should -Invoke Start-Process -Times 3 -Exactly
			Should -Invoke Wait-BrowserWindowReady -Times 0
		}
	}

	It "warns and launches nothing when no browser is given and DefaultBrowser is blank (empty base)" {
		$global:Configuration.Universal.DefaultBrowser = ''
		Mock Write-LogWarning { }

		Open-Browser -Groups Work

		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "DefaultBrowser is not configured" }
		Should -Invoke Start-Process -Times 0
	}
}
