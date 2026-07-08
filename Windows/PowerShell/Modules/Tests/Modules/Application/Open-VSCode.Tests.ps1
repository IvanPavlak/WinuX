#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-VSCode.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
}

Describe "Open-VSCode" {
	BeforeEach {
		$global:MachineSpecificPaths = @{}
		$global:Configuration = @{
			VSCodeProjects = @(
				@{ Name = 'WinuX'; Path = 'Development.WinuX' }
			)
		}

		Mock Write-Host { }
		Mock Resolve-Selection { @('WinuX') }
		Mock Invoke-Command { 'C:\Repos\WinuX' }
		Mock Test-Path { $true }
		Mock Test-ProjectAlreadyOpen { $false }
		Mock Get-Process { $null }
		Mock Start-Process { }
	}

	It "returns early when VSCodeProjects configuration is missing" {
		$global:Configuration = @{}
		Open-VSCode -Folder WinuX
		Should -Invoke Start-Process -Times 0
	}

	It "opens configured folder in a new VS Code window when project is not already open" {
		Open-VSCode -Folder WinuX

		Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter {
			$OptionList -contains 'WinuX' -and $InputObject -contains 'WinuX'
		}
		Should -Invoke Test-ProjectAlreadyOpen -Times 1 -Exactly -ParameterFilter {
			$ProjectName -eq 'WinuX' -and $ProcessName -eq 'Code'
		}
		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq 'code' -and $ArgumentList[0] -eq '-n' -and $ArgumentList[1] -eq '"C:\Repos\WinuX"'
		}
	}

	It "does not launch VS Code for a project already detected as open" {
		Mock Test-ProjectAlreadyOpen { $true }

		Open-VSCode -Folder WinuX

		Should -Invoke Start-Process -Times 0
	}
}
