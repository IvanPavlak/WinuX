#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-VSCode.ps1"
	. "$AppFunctionsPath\Start-VSCodeDetached.ps1"
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
		Mock Start-VSCodeDetached { }
	}

	It "returns early when VSCodeProjects configuration is missing" {
		$global:Configuration = @{}
		Open-VSCode -Folder WinuX
		Should -Invoke Start-VSCodeDetached -Times 0
	}

	It "opens configured folder detached in a new VS Code window when project is not already open" {
		Open-VSCode -Folder WinuX

		Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter {
			$OptionList -contains 'WinuX' -and $InputObject -contains 'WinuX'
		}
		Should -Invoke Test-ProjectAlreadyOpen -Times 1 -Exactly -ParameterFilter {
			$ProjectName -eq 'WinuX' -and $ProcessName -eq 'Code'
		}
		Should -Invoke Start-VSCodeDetached -Times 1 -Exactly -ParameterFilter {
			$ArgumentList[0] -eq '-n' -and $ArgumentList[1] -eq '"C:\Repos\WinuX"'
		}
	}

	It "does not launch VS Code for a project already detected as open" {
		Mock Test-ProjectAlreadyOpen { $true }

		Open-VSCode -Folder WinuX

		Should -Invoke Start-VSCodeDetached -Times 0
	}

	It "launches VS Code detached without a folder with -Default when Code is not running" {
		Open-VSCode -Default

		Should -Invoke Resolve-Selection -Times 0
		Should -Invoke Start-VSCodeDetached -Times 1 -Exactly -ParameterFilter { -not $ArgumentList }
	}

	It "does not launch a bare VS Code with -Default when Code is already running" {
		Mock Get-Process { [PSCustomObject]@{ Name = 'Code' } }

		Open-VSCode -Default

		Should -Invoke Start-VSCodeDetached -Times 0
	}

	It "reports a missing folder path and launches nothing" {
		Mock Test-Path { $false }

		Open-VSCode -Folder WinuX

		Should -Invoke Start-VSCodeDetached -Times 0
	}
}
