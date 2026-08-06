#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	# The unconfigured-section guards warn through Confirm-ConfigValue (Helper);
	# dot-source it (and its Test-ConfigValue dependency) so the Write-LogWarning
	# mocks in these tests apply to the guard's warning.
	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"

	# SymbolicLinkMaker orchestrates these three - dot-source them so the tests
	# exercise the real discovery/creation pipeline end to end.
	. "$FunctionsPath\Get-SymbolicLinkEntries.ps1"
	. "$FunctionsPath\New-WindowsSymbolicLink.ps1"
	. "$FunctionsPath\New-WSLSymbolicLink.ps1"
	. "$FunctionsPath\SymbolicLinkMaker.ps1"
}

Describe "SymbolicLinkMaker" {
	BeforeEach {
		$script:MachineSpecificPaths = @{}
		$script:Configuration = [PSCustomObject]@{
			DefaultWSLDistribution = "Ubuntu"
		}

		Mock Test-AdminPrivileges { }
		Mock DetermineMachineType { "PC" }
		Mock Test-WSLDistributionInstalled { $true }
		# The WSL branch drives control flow off $LASTEXITCODE after every wsl call;
		# pin it to success so the mock is deterministic regardless of prior commands.
		Mock wsl { $global:LASTEXITCODE = 0 }
		Mock New-Item { }
		Mock Remove-Item { }
		Mock Test-Path { $true }
		Mock Write-Host { }
		Mock Write-LogTitle { }
		Mock Write-LogError { }
		Mock Write-LogWarning { }
	}

	It "returns with a warning when SymbolicLinks configuration is missing" {
		{ SymbolicLinkMaker } | Should -Not -Throw

		Should -Invoke DetermineMachineType -Times 1
		Should -Invoke Write-LogTitle -Times 1
		Should -Invoke Write-LogError -Times 0
		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "SymbolicLinks not configured" }
	}

	It "returns with a warning when SymbolicLinks is an empty hashtable" {
		$script:MachineSpecificPaths = @{ SymbolicLinks = @{} }

		{ SymbolicLinkMaker } | Should -Not -Throw

		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "SymbolicLinks not configured" }
	}

	Context "Scope and Name filtering" {
		BeforeEach {
			$script:MachineSpecificPaths = @{
				SymbolicLinks = @{
					Git       = @{
						Path   = "C:\Users\Test\.gitconfig"
						Target = "C:\Repo\Git\.gitconfig"
					}
					WSLSSH    = @{
						Path   = "/home/test/.ssh/config"
						Target = "/mnt/c/Users/Test/.ssh/config"
					}
					PowerToys = @{
						Settings = @{
							Path   = "C:\Users\Test\PowerToys\settings.json"
							Target = "C:\Repo\FancyZones\settings.json"
						}
					}
				}
			}
		}

		It "processes every entry by default" {
			{ SymbolicLinkMaker } | Should -Not -Throw

			# Windows links: Git + PowerToys.Settings
			Should -Invoke New-Item -Times 2 -Exactly
			# WSL link: at least the `ln -s` for WSLSSH
			Should -Invoke wsl -ParameterFilter { $args -contains 'ln' } -Times 1 -Exactly
		}

		It "-Scope WSL touches only WSL entries and skips Windows ones silently" {
			{ SymbolicLinkMaker -Scope WSL } | Should -Not -Throw

			Should -Invoke New-Item -Times 0
			Should -Invoke wsl -ParameterFilter { $args -contains 'ln' } -Times 1 -Exactly
		}

		It "-Scope Windows touches only Windows entries and never calls wsl.exe" {
			{ SymbolicLinkMaker -Scope Windows } | Should -Not -Throw

			Should -Invoke New-Item -Times 2 -Exactly
			Should -Invoke wsl -Times 0
			Should -Invoke Test-WSLDistributionInstalled -Times 0
		}

		It "-Name limits the run to matching top-level entries" {
			{ SymbolicLinkMaker -Name Git } | Should -Not -Throw

			Should -Invoke New-Item -Times 1 -Exactly
			Should -Invoke wsl -Times 0
		}

		It "-Name matches a group and processes everything beneath it" {
			{ SymbolicLinkMaker -Name PowerToys } | Should -Not -Throw

			Should -Invoke New-Item -Times 1 -Exactly
		}

		It "-Name reaches nested entries via the dotted path" {
			{ SymbolicLinkMaker -Name "PowerToys.Settings" } | Should -Not -Throw

			Should -Invoke New-Item -Times 1 -Exactly
		}

		It "-Name supports wildcards" {
			{ SymbolicLinkMaker -Name "WSL*" } | Should -Not -Throw

			Should -Invoke New-Item -Times 0
			Should -Invoke wsl -ParameterFilter { $args -contains 'ln' } -Times 1 -Exactly
		}

		It "-Name and -Scope combine" {
			{ SymbolicLinkMaker -Scope Windows -Name "WSL*" } | Should -Not -Throw

			Should -Invoke New-Item -Times 0
			Should -Invoke wsl -Times 0
		}

		It "prints the full group header, not its first character" {
			Mock Write-LogStep { }

			{ SymbolicLinkMaker -Name PowerToys } | Should -Not -Throw

			# Regression: single-group entries once printed "[P]" because the group
			# array collapsed to a bare string
			Should -Invoke Write-LogStep -Times 1 -Exactly -ParameterFilter { $Message -match '^\[PowerToys\]$' }
			Should -Invoke Write-LogStep -Times 1 -Exactly -ParameterFilter { $Message -match '^  \[Settings\]$' }
		}
	}
}
