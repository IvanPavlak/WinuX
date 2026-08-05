#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Sync-AppPins.ps1"
	. "$FunctionsPath\Get-PinnedApps.ps1"
	. "$ModuleRoot\Bootstrap\Functions\Import-AppCsv.ps1"

	# Function stubs standing in for the CLIs, so the tests do not depend on any manager being
	# installed on the machine running them. `scoop` additionally resolves to an external script that
	# Mock cannot bind in script scope even when it is present.
	function winget { }
	function scoop { }
	function choco { }
}

Describe "Sync-AppPins" {
	BeforeEach {
		Mock Show-PinnedAppsWarning { }
		Mock Write-LogWarning { }
		Mock Write-Host { }
		Mock winget { }
		Mock scoop { }
		Mock choco { }
	}

	Context "WinGet" {
		It "pins every version-locked app" {
			Mock Import-AppCsv {
				@(
					[pscustomobject]@{ App = 'Pinned.App'; Version = '1.2.3' }
					[pscustomobject]@{ App = 'Latest.App'; Version = 'Latest' }
				)
			}

			Sync-AppPins -PackageManager WinGet

			Should -Invoke winget -ParameterFilter {
				$args -contains 'pin' -and $args -contains 'add' -and $args -contains 'Pinned.App'
			} -Times 1 -Exactly
		}

		It "removes a stale pin for an app that is back to Latest" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'Latest.App'; Version = 'Latest' }) }
			# `winget pin list --id Latest.App` still reports the app => a pin survived from an
			# earlier run when it was version-locked.
			Mock winget -ParameterFilter { $args -contains 'list' } -MockWith { 'Latest.App  1.2.3  Pinning' }

			Sync-AppPins -PackageManager WinGet

			Should -Invoke winget -ParameterFilter {
				$args -contains 'pin' -and $args -contains 'remove' -and $args -contains 'Latest.App'
			} -Times 1 -Exactly
		}

		It "leaves an unpinned app alone when no pin exists for it" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'Latest.App'; Version = 'Latest' }) }
			Mock winget -ParameterFilter { $args -contains 'list' } -MockWith { 'No pins are configured.' }

			Sync-AppPins -PackageManager WinGet

			Should -Invoke winget -ParameterFilter { $args -contains 'remove' } -Times 0
		}

		It "never removes a pin for an app outside the managed list" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'Latest.App'; Version = 'Latest' }) }
			Mock winget -ParameterFilter { $args -contains 'list' } -MockWith { 'No pins are configured.' }

			Sync-AppPins -PackageManager WinGet

			# Only the managed app is ever interrogated - a hand-made pin for anything else is not
			# WinuX's to drop.
			Should -Invoke winget -ParameterFilter { $args -contains 'list' } -Times 1 -Exactly
		}
	}

	Context "Scoop" {
		BeforeEach {
			# `scoop export` is the single read of installed / held / global state.
			Mock scoop -ParameterFilter { $args -contains 'export' } -MockWith {
				'{"apps":[{"Name":"pinnedapp","Info":""},{"Name":"latestapp","Info":"Held package"},{"Name":"globalapp","Info":"Global install, Held package"}]}'
			}
		}

		It "holds a version-locked app through scoop hold" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'pinnedapp'; Version = '1.2.3' }) }

			Sync-AppPins -PackageManager Scoop

			Should -Invoke scoop -ParameterFilter { $args -contains 'hold' -and $args -contains 'pinnedapp' } -Times 1 -Exactly
		}

		It "releases a stale hold for an app that is back to latest" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'latestapp'; Version = 'latest' }) }

			Sync-AppPins -PackageManager Scoop

			Should -Invoke scoop -ParameterFilter { $args -contains 'unhold' -and $args -contains 'latestapp' } -Times 1 -Exactly
		}

		It "holds nothing when the app is not installed, since a hold needs an installed app" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'absentapp'; Version = '1.2.3' }) }

			Sync-AppPins -PackageManager Scoop

			Should -Invoke scoop -ParameterFilter { $args -contains 'hold' } -Times 0
			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}

		It "follows the installed scope rather than the CSV, passing -g for a global app" {
			# The row says Global=false, but the app is installed globally - hold must follow reality.
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'globalapp'; Version = 'latest'; Global = 'false' }) }

			Sync-AppPins -PackageManager Scoop

			Should -Invoke scoop -ParameterFilter {
				$args -contains 'unhold' -and $args -contains '-g' -and $args -contains 'globalapp'
			} -Times 1 -Exactly
		}

		It "does not pass -g for a user-scoped app" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'latestapp'; Version = 'latest' }) }

			Sync-AppPins -PackageManager Scoop

			Should -Invoke scoop -ParameterFilter { $args -contains 'unhold' -and $args -contains '-g' } -Times 0
		}

		It "releases nothing when the app holds no hold" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'pinnedapp'; Version = 'latest' }) }

			Sync-AppPins -PackageManager Scoop

			Should -Invoke scoop -ParameterFilter { $args -contains 'unhold' } -Times 0
		}

		It "gives up on reconciliation rather than guessing when scoop export fails" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'pinnedapp'; Version = '1.2.3' }) }
			Mock scoop -ParameterFilter { $args -contains 'export' } -MockWith { 'not json' }

			Sync-AppPins -PackageManager Scoop

			Should -Invoke scoop -ParameterFilter { $args -contains 'hold' } -Times 0
			Should -Invoke scoop -ParameterFilter { $args -contains 'unhold' } -Times 0
		}
	}

	Context "Chocolatey" {
		It "treats any version as a pin, since an empty cell means latest" {
			Mock Import-AppCsv {
				@(
					[pscustomobject]@{ App = 'pinnedapp'; Version = '1.2.3' }
					[pscustomobject]@{ App = 'latestapp'; Version = '' }
				)
			}
			Mock choco -ParameterFilter { $args -contains 'list' } -MockWith { @() }

			Sync-AppPins -PackageManager Chocolatey

			Should -Invoke choco -ParameterFilter {
				$args -contains 'add' -and $args -contains '--name=pinnedapp'
			} -Times 1 -Exactly
		}

		It "removes a stale pin reported by choco pin list" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'latestapp'; Version = '' }) }
			Mock choco -ParameterFilter { $args -contains 'list' } -MockWith { 'latestapp|1.2.3' }

			Sync-AppPins -PackageManager Chocolatey

			Should -Invoke choco -ParameterFilter {
				$args -contains 'remove' -and $args -contains '--name=latestapp'
			} -Times 1 -Exactly
		}

		It "removes nothing when choco reports no pins" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'latestapp'; Version = '' }) }
			Mock choco -ParameterFilter { $args -contains 'list' } -MockWith { @() }

			Sync-AppPins -PackageManager Chocolatey

			Should -Invoke choco -ParameterFilter { $args -contains 'remove' } -Times 0
		}
	}
}
