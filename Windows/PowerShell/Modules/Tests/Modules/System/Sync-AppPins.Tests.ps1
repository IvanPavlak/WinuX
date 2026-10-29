#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Sync-AppPins.ps1"
	. "$FunctionsPath\Get-PinnedApps.ps1"
	. "$FunctionsPath\Invoke-PackageManagerCommand.ps1"
	. "$FunctionsPath\Get-WinGetPinnedIds.ps1"
	. "$ModuleRoot\Bootstrap\Functions\Import-AppCsv.ps1"
}

Describe "Sync-AppPins" {
	BeforeEach {
		Mock Show-PinnedAppsWarning { }
		Mock Write-LogWarning { }
		Mock Write-Host { }
		# Every winget, scoop and choco call goes through Invoke-PackageManagerCommand, the one place a
		# stalled manager is stopped - so that is the seam the tests observe, never the CLI itself.
		# WinGet's pin state is read through Get-WinGetPinnedIds, which has its own tests.
		Mock Invoke-PackageManagerCommand { @() }
		Mock Get-WinGetPinnedIds { @() }
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

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter {
				$PackageManager -eq 'WinGet' -and ($Arguments[0..1] -join ' ') -eq 'pin add' -and $Arguments -contains '--blocking' -and $Arguments -contains 'Pinned.App'
			} -Times 1 -Exactly
			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter { $Arguments -contains 'add' -and $Arguments -contains 'Latest.App' } -Times 0
		}

		It "removes a stale pin for an app that is back to Latest" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'Latest.App'; Version = 'Latest' }) }
			# `winget pin list` still reports the app => a pin survived from an earlier run when it was
			# version-locked.
			Mock Get-WinGetPinnedIds { 'Latest.App' }

			Sync-AppPins -PackageManager WinGet

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter {
				$PackageManager -eq 'WinGet' -and ($Arguments[0..1] -join ' ') -eq 'pin remove' -and $Arguments -contains 'Latest.App'
			} -Times 1 -Exactly
		}

		It "leaves an unpinned app alone when no pin exists for it" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'Latest.App'; Version = 'Latest' }) }

			Sync-AppPins -PackageManager WinGet

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter { $Arguments -contains 'remove' } -Times 0
		}

		It "reads the pin state once, asking only about the managed apps back to Latest" {
			Mock Import-AppCsv {
				@(
					[pscustomobject]@{ App = 'Pinned.App'; Version = '1.2.3' }
					[pscustomobject]@{ App = 'Latest.App'; Version = 'Latest' }
					[pscustomobject]@{ App = 'Other.App'; Version = 'Latest' }
				)
			}

			Sync-AppPins -PackageManager WinGet

			# One read for every app rather than one per app, and only the managed unpinned apps are
			# looked for - a hand-made pin for anything else is not WinuX's to drop.
			Should -Invoke Get-WinGetPinnedIds -Times 1 -Exactly -ParameterFilter { ($AppId -join ',') -eq 'Latest.App,Other.App' }
		}

		It "stops with the error when the winget pin listing stalls, pinning nothing" {
			Mock Import-AppCsv {
				@(
					[pscustomobject]@{ App = 'Pinned.App'; Version = '1.2.3' }
					[pscustomobject]@{ App = 'Latest.App'; Version = 'Latest' }
				)
			}
			Mock Get-WinGetPinnedIds { throw 'stalled' }

			{ Sync-AppPins -PackageManager WinGet } | Should -Throw

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter { $Arguments -contains 'add' -or $Arguments -contains 'remove' } -Times 0
		}
	}

	Context "Scoop" {
		BeforeEach {
			# `scoop export` is the single read of installed / held / global state. The helper returns
			# lines, so the JSON arrives split across several of them.
			Mock Invoke-PackageManagerCommand -ParameterFilter { $PackageManager -eq 'Scoop' -and $Arguments[0] -eq 'export' } -MockWith {
				'{"apps":['
				'{"Name":"pinnedapp","Info":""},{"Name":"latestapp","Info":"Held package"},'
				'{"Name":"globalapp","Info":"Global install, Held package"}]}'
			}
		}

		It "holds a version-locked app through scoop hold" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'pinnedapp'; Version = '1.2.3' }) }

			Sync-AppPins -PackageManager Scoop

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter { $PackageManager -eq 'Scoop' -and ($Arguments -join ' ') -eq 'hold pinnedapp' } -Times 1 -Exactly
		}

		It "releases a stale hold for an app that is back to latest" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'latestapp'; Version = 'latest' }) }

			Sync-AppPins -PackageManager Scoop

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter { $PackageManager -eq 'Scoop' -and ($Arguments -join ' ') -eq 'unhold latestapp' } -Times 1 -Exactly
		}

		It "holds nothing when the app is not installed, since a hold needs an installed app" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'absentapp'; Version = '1.2.3' }) }

			Sync-AppPins -PackageManager Scoop

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter { $Arguments[0] -eq 'hold' } -Times 0
			Should -Invoke Write-LogWarning -Times 1 -Exactly
		}

		It "follows the installed scope rather than the CSV, passing -g for a global app" {
			# The row says Global=false, but the app is installed globally - hold must follow reality.
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'globalapp'; Version = 'latest'; Global = 'false' }) }

			Sync-AppPins -PackageManager Scoop

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter { $PackageManager -eq 'Scoop' -and ($Arguments -join ' ') -eq 'unhold -g globalapp' } -Times 1 -Exactly
		}

		It "does not pass -g for a user-scoped app" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'latestapp'; Version = 'latest' }) }

			Sync-AppPins -PackageManager Scoop

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter { $Arguments[0] -eq 'unhold' -and $Arguments -contains '-g' } -Times 0
		}

		It "releases nothing when the app holds no hold" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'pinnedapp'; Version = 'latest' }) }

			Sync-AppPins -PackageManager Scoop

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter { $Arguments[0] -eq 'unhold' } -Times 0
		}

		It "gives up on reconciliation rather than guessing when scoop export answers something that is not JSON" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'pinnedapp'; Version = '1.2.3' }) }
			Mock Invoke-PackageManagerCommand -ParameterFilter { $PackageManager -eq 'Scoop' -and $Arguments[0] -eq 'export' } -MockWith { 'not json' }

			Sync-AppPins -PackageManager Scoop

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter { $Arguments[0] -in 'hold', 'unhold' } -Times 0
		}

		It "stops with the error when scoop export stalls, changing no hold" {
			Mock Import-AppCsv {
				@(
					[pscustomobject]@{ App = 'pinnedapp'; Version = '1.2.3' }
					[pscustomobject]@{ App = 'latestapp'; Version = 'latest' }
				)
			}
			Mock Invoke-PackageManagerCommand -ParameterFilter { $PackageManager -eq 'Scoop' -and $Arguments[0] -eq 'export' } -MockWith { throw 'stalled' }

			{ Sync-AppPins -PackageManager Scoop } | Should -Throw

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter { $Arguments[0] -in 'hold', 'unhold' } -Times 0
		}
	}

	Context "Chocolatey" {
		It "pins a row carrying a real version" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'pinnedapp'; Version = '1.2.3' }) }

			Sync-AppPins -PackageManager Chocolatey

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter {
				$PackageManager -eq 'Chocolatey' -and ($Arguments -join ' ') -eq 'pin add --name=pinnedapp'
			} -Times 1 -Exactly
		}

		It "never pins a row tracking the latest, whether the cell says latest or is empty" -ForEach @(
			@{ Version = 'latest' }
			@{ Version = 'Latest' }
			@{ Version = '' }
		) {
			# A "latest" row was once read as a version, and `choco pin add` froze the app at
			# whatever it had installed - the opposite of what the row asks for.
			$rowVersion = $Version
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'latestapp'; Version = $rowVersion }) }

			Sync-AppPins -PackageManager Chocolatey

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter { $Arguments -contains 'add' } -Times 0
		}

		It "removes a stale pin reported by choco pin list" -ForEach @(
			@{ Version = 'latest' }
			@{ Version = '' }
		) {
			$rowVersion = $Version
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'latestapp'; Version = $rowVersion }) }
			Mock Invoke-PackageManagerCommand -ParameterFilter { ($Arguments -join ' ') -eq 'pin list -r' } -MockWith { 'latestapp|1.2.3' }

			Sync-AppPins -PackageManager Chocolatey

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter {
				$PackageManager -eq 'Chocolatey' -and ($Arguments -join ' ') -eq 'pin remove --name=latestapp'
			} -Times 1 -Exactly
		}

		It "removes nothing when choco reports no pins" {
			Mock Import-AppCsv { @([pscustomobject]@{ App = 'latestapp'; Version = 'latest' }) }

			Sync-AppPins -PackageManager Chocolatey

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter { $Arguments -contains 'remove' } -Times 0
		}

		It "stops with the error when choco pin list stalls, changing no pin" {
			Mock Import-AppCsv {
				@(
					[pscustomobject]@{ App = 'pinnedapp'; Version = '1.2.3' }
					[pscustomobject]@{ App = 'latestapp'; Version = 'latest' }
				)
			}
			Mock Invoke-PackageManagerCommand -ParameterFilter { ($Arguments -join ' ') -eq 'pin list -r' } -MockWith { throw 'stalled' }

			{ Sync-AppPins -PackageManager Chocolatey } | Should -Throw

			Should -Invoke Invoke-PackageManagerCommand -ParameterFilter { $Arguments -contains 'add' -or $Arguments -contains 'remove' } -Times 0
		}
	}
}
