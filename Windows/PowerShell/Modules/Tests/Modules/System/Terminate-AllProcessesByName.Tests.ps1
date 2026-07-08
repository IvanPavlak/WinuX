#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Terminate-AllProcessesByName.ps1"

	# Stub Test-WindowTitleMatch since it's from the same module
	function Test-WindowTitleMatch { param($ProcessName, $WindowTitle, $Patterns) $false }
}

Describe "Terminate-AllProcessesByName" {
	BeforeEach {
		Mock Write-Host { }
		Mock Stop-Process { }
	}

	Context "When target processes are running" {
		It "Should terminate found processes" {
			$mockProcess = [PSCustomObject]@{ ProcessName = "Code"; Id = 1234; MainWindowTitle = "file.ps1 - VS Code" }
			Mock Get-Process { $mockProcess } -ParameterFilter { $Name -eq "Code" }
			Mock Get-Process { $null } -ParameterFilter { $Name -ne "Code" }

			Terminate-AllProcessesByName

			Should -Invoke Stop-Process -Times 1 -Exactly
		}
	}

	Context "When no target processes are running" {
		It "Should not call Stop-Process" {
			Mock Get-Process { $null }

			Terminate-AllProcessesByName

			Should -Invoke Stop-Process -Times 0
		}
	}

	Context "When Exclude patterns are provided" {
		It "Should skip processes matching exclusion patterns" {
			$mockProcess = [PSCustomObject]@{ ProcessName = "Code"; Id = 1234; MainWindowTitle = "Important Project - VS Code" }
			Mock Get-Process { $mockProcess } -ParameterFilter { $Name -eq "Code" }
			Mock Get-Process { $null } -ParameterFilter { $Name -ne "Code" }
			Mock Test-WindowTitleMatch { $true } -ParameterFilter { $Patterns -contains "*Important*" }

			Terminate-AllProcessesByName -Exclude "*Important*"

			Should -Invoke Stop-Process -Times 0
		}

		It "Should terminate processes that don't match exclusion patterns" {
			$mockProcess1 = [PSCustomObject]@{ ProcessName = "Code"; Id = 1; MainWindowTitle = "Excluded Project" }
			$mockProcess2 = [PSCustomObject]@{ ProcessName = "Code"; Id = 2; MainWindowTitle = "Other Project" }
			Mock Get-Process { @($mockProcess1, $mockProcess2) } -ParameterFilter { $Name -eq "Code" }
			Mock Get-Process { $null } -ParameterFilter { $Name -ne "Code" }
			Mock Test-WindowTitleMatch {
				param($ProcessName, $WindowTitle, $Patterns)
				$WindowTitle -eq "Excluded Project"
			}

			Terminate-AllProcessesByName -Exclude "*Excluded*"

			Should -Invoke Stop-Process -Times 1
		}
	}
}
