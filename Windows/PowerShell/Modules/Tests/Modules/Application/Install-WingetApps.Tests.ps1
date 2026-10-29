#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Install-WingetApps.ps1"
	# Dot-source the machine-scope gate so the Machine-column filtering resolves even in
	# sessions whose imported Bootstrap module predates the Test-MachineTypeScope export.
	. (Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions\Test-MachineTypeScope.ps1")
	# Same reason for the layered CSV reader the installer now reads through.
	. (Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions\Import-AppCsv.ps1")
	# Dot-sourced so they exist to Mock: every short winget call goes through them, so they are the
	# seam observed here, never winget itself.
	. (Join-Path (Get-RepositoryPath).Modules "System\Functions\Invoke-PackageManagerCommand.ps1")
	. (Join-Path (Get-RepositoryPath).Modules "System\Functions\Get-WinGetPinnedIds.ps1")
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
}

Describe "Install-WingetApps" {
	BeforeEach {
		Mock Write-Host { }
		Mock Test-AdminPrivileges { }
		Mock DetermineMachineType { 'Laptop' }
		Mock Invoke-PackageManagerCommand { @() }
		Mock Get-WinGetPinnedIds { @() }
		Mock Write-LogWarning { }
		Mock Invoke-Expression { }

		$global:MachineSpecificPaths = @{ Projects = @{ Self = @{ Root = $TestDrive } } }
		$global:Configuration = @{ BootstrapConfig = @{ DataFiles = @{ WinGetApps = 'winget.csv' } } }
	}

	It "invokes winget install expression only for matching machine entries" {
		$csv = @'
App,Machine,Version,Scope,Interactive,Source
Git.Git,Laptop,Latest,d,n,w
XP9KHM4BK9FZ7Q,PC,Latest,d,n,s
'@
		Set-Content -Path (Join-Path $TestDrive 'winget.csv') -Value $csv

		Install-WinGetApps

		Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter { $Command -like '*winget install*Git.Git*' }
	}

	It "reports unknown machine tokens via Write-LogError and skips the row" {
		$global:Configuration.ValidMachineTypes = @('PC', 'Laptop', 'Work', 'Test')
		Mock Write-LogError { }
		$csv = @'
App,Machine,Version,Scope,Interactive,Source
Git.Git,Labtop,Latest,d,n,w
'@
		Set-Content -Path (Join-Path $TestDrive 'winget.csv') -Value $csv

		Install-WinGetApps

		Should -Invoke Write-LogError -ParameterFilter { $Message -like '*Labtop*' }
		Should -Invoke Invoke-Expression -Times 0 -ParameterFilter { $Command -like '*winget install*' }
	}

	Context "pins" {
		BeforeEach {
			$csv = @'
App,Machine,Version,Scope,Interactive,Source
Git.Git,All,Latest,d,n,w
Pinned.App,All,1.2.3,d,n,w
'@
			Set-Content -Path (Join-Path $TestDrive 'winget.csv') -Value $csv
		}

		It "reads the pins of the Latest apps in one call, never the version-locked ones" {
			Install-WinGetApps

			Should -Invoke Get-WinGetPinnedIds -Times 1 -Exactly -ParameterFilter { ($AppId -join ',') -eq 'Git.Git' }
		}

		It "removes a leftover pin from an app back to Latest before installing it" {
			Mock Get-WinGetPinnedIds { 'Git.Git' }

			Install-WinGetApps

			Should -Invoke Invoke-PackageManagerCommand -Times 1 -Exactly -ParameterFilter {
				$PackageManager -eq 'WinGet' -and $Arguments[0] -eq 'pin' -and $Arguments -contains 'remove' -and $Arguments -contains 'Git.Git'
			}
		}

		It "removes no pin when none is left over" {
			Install-WinGetApps

			Should -Invoke Invoke-PackageManagerCommand -Times 0 -ParameterFilter { $Arguments -contains 'remove' }
		}

		It "still installs every app when the pin listing stalls" {
			# A stalled read leaves the pins as they are; it must not stop the installs.
			Mock Get-WinGetPinnedIds { throw 'stalled' }

			Install-WinGetApps

			Should -Invoke Invoke-PackageManagerCommand -Times 0 -ParameterFilter { $Arguments -contains 'remove' }
			Should -Invoke Invoke-Expression -Times 2 -Exactly -ParameterFilter { $Command -like '*winget install*' }
		}
	}

	Context "presence check after a non-zero install exit code" {
		BeforeEach {
			$csv = @'
App,Machine,Version,Scope,Interactive,Source
Git.Git,All,Latest,d,n,w
'@
			Set-Content -Path (Join-Path $TestDrive 'winget.csv') -Value $csv
			Mock Write-LogError { }
			Mock Write-LogSuccess { }
			Mock Invoke-Expression { $global:LASTEXITCODE = 1 }
		}

		It "counts the app as installed when winget list finds it" {
			Mock Invoke-PackageManagerCommand { $global:LASTEXITCODE = 0 } -ParameterFilter { $Arguments[0] -eq 'list' }

			Install-WinGetApps

			Should -Invoke Write-LogError -Times 0 -ParameterFilter { $Message -like '*Install FAILED*' }
		}

		It "reports the install as failed when winget list does not find the app" {
			Mock Invoke-PackageManagerCommand { $global:LASTEXITCODE = 1 } -ParameterFilter { $Arguments[0] -eq 'list' }

			Install-WinGetApps

			Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like '*Install FAILED*Git.Git*' }
		}

		It "reports the install as failed when the check itself stalls" {
			Mock Invoke-PackageManagerCommand { throw 'stalled' } -ParameterFilter { $Arguments[0] -eq 'list' }

			Install-WinGetApps

			Should -Invoke Write-LogError -Times 1 -Exactly -ParameterFilter { $Message -like '*Install FAILED*Git.Git*' }
		}
	}

	It "goes on to the installs when priming a source agreement stalls" {
		$csv = @'
App,Machine,Version,Scope,Interactive,Source
Git.Git,All,Latest,d,n,w
'@
		Set-Content -Path (Join-Path $TestDrive 'winget.csv') -Value $csv
		Mock Invoke-PackageManagerCommand { throw 'stalled' } -ParameterFilter { $Arguments[0] -eq 'search' }

		Install-WinGetApps

		Should -Invoke Invoke-PackageManagerCommand -Times 2 -Exactly -ParameterFilter { $Arguments[0] -eq 'search' }
		Should -Invoke Invoke-Expression -Times 1 -Exactly -ParameterFilter { $Command -like '*winget install*Git.Git*' }
	}
}
