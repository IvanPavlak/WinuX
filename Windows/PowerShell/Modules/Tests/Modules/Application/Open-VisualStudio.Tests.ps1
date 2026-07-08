#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-VisualStudio.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
}

Describe "Open-VisualStudio" {
	BeforeEach {
		$global:MachineSpecificPaths = @{}
		$global:Configuration = @{
			VisualStudioSolutions = @(
				@{ Name = 'WinuX'; Solution = 'Development.WinuXSln' }
			)
			Universal             = @{
				VisualStudio2026Exe = 'C:\Program Files\VS\devenv.exe'
			}
		}

		Mock Write-Host { }
		Mock Test-Path { $true }
		Mock Resolve-Selection { @('WinuX') }
		Mock Invoke-Command { 'C:\Repos\WinuX\WinuX.sln' }
		Mock Test-ProjectAlreadyOpen { $false }
		Mock Get-Process { $null }
		Mock Start-Process { }
	}

	It "returns early when VisualStudioSolutions configuration is missing" {
		$global:Configuration = @{ Universal = @{ VisualStudio2026Exe = 'C:\Program Files\VS\devenv.exe' } }

		Open-VisualStudio -Solution WinuX

		Should -Invoke Start-Process -Times 0
	}

	It "opens selected solution when mapping resolves and solution is not already open" {
		Open-VisualStudio -Solution WinuX

		Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter {
			$OptionList -contains 'WinuX' -and $InputObject -contains 'WinuX'
		}
		Should -Invoke Test-ProjectAlreadyOpen -Times 1 -Exactly -ParameterFilter {
			$ProjectName -eq 'WinuX' -and $ProcessName -eq 'devenv'
		}
		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq 'C:\Program Files\VS\devenv.exe' -and $ArgumentList -eq 'C:\Repos\WinuX\WinuX.sln'
		}
	}
}
