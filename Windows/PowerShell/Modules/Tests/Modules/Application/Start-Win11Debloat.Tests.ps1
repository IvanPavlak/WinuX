#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Start-Win11Debloat.ps1"
	. "$AppFunctionsPath\Sync-Win11DebloatSettings.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
}

Describe "Start-Win11Debloat" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogError { }
		Mock Write-LogSuccess { }
		Mock Test-AdminPrivileges { }
		Mock Resolve-Selection { 'Use saved settings' }
		# The saved-settings link is Sync-Win11DebloatSettings' job and is covered by its own tests.
		Mock Sync-Win11DebloatSettings { $true }
	}

	It "returns when configured Win11Debloat script path does not exist" {
		$global:MachineSpecificPaths = @{
			Projects = @{ Self = @{ Root = 'C:\Repo\WinuX' } }
		}
		$global:Configuration = @{
			BootstrapConfig = @{ LocalScripts = @{ Win11Debloat = 'C:\Repo\WinuX\Windows\Win11Debloat\vendor\Win11Debloat.ps1' } }
		}
		Mock Test-Path { $false }

		Start-Win11Debloat

		Should -Invoke Resolve-Selection -Times 0
	}

	It "runs script through Windows PowerShell with -RunSavedSettings when a non-empty saved-settings file exists" {
		# The stub records the edition it ran under, so the assertion proves Win11Debloat was launched
		# through powershell.exe (Desktop) instead of the pwsh session the tests run in, which the
		# vendored release refuses to start under.
		$scriptPath = Join-Path $TestDrive 'Win11Debloat.ps1'
		$invocationPath = Join-Path $TestDrive 'Invocation.txt'
		$scriptContent = @'
param([switch]$RunSavedSettings,[switch]$Silent)
$invocationPath = Join-Path (Split-Path -Parent $PSCommandPath) 'Invocation.txt'
Set-Content -LiteralPath $invocationPath -Value @($PSVersionTable.PSEdition, $RunSavedSettings.IsPresent, $Silent.IsPresent)
'@
		Set-Content -Path $scriptPath -Value $scriptContent

		$global:MachineSpecificPaths = @{
			Projects = @{ Self = @{ Root = $TestDrive } }
		}
		$global:Configuration = @{
			BootstrapConfig = @{ LocalScripts = @{ Win11Debloat = $scriptPath } }
		}

		Mock Test-Path { $true }

		Start-Win11Debloat

		Get-Content -LiteralPath $invocationPath | Should -Be @('Desktop', 'True', 'True')
		Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq 'Debloating with saved settings completed!' }
		Should -Invoke Sync-Win11DebloatSettings -Times 1 -Exactly
	}

	It "offers no saved settings when Sync-Win11DebloatSettings reports none" {
		$global:MachineSpecificPaths = @{
			Projects = @{ Self = @{ Root = $TestDrive } }
		}
		$global:Configuration = @{
			BootstrapConfig = @{ LocalScripts = @{ Win11Debloat = (Join-Path $TestDrive 'Win11Debloat.ps1') } }
		}

		Mock Test-Path { $true }
		Mock Sync-Win11DebloatSettings { $false }
		Mock Resolve-Selection { "Don't debloat" }
		Mock Write-LogWarning { }

		Start-Win11Debloat

		Should -Invoke Resolve-Selection -Times 1 -Exactly -ParameterFilter { $OptionList -notcontains 'Use saved settings' -and $OptionList -contains 'Debloat' }
	}

	It "syncs the saved settings again after an interactive run, so a first run's choices reach the repository" {
		$scriptPath = Join-Path $TestDrive 'Win11Debloat-Interactive.ps1'
		Set-Content -Path $scriptPath -Value 'exit 0'

		$global:MachineSpecificPaths = @{
			Projects = @{ Self = @{ Root = $TestDrive } }
		}
		$global:Configuration = @{
			BootstrapConfig = @{ LocalScripts = @{ Win11Debloat = $scriptPath } }
		}

		Mock Test-Path { $true }
		Mock Resolve-Selection { 'Debloat' }

		Start-Win11Debloat

		Should -Invoke Sync-Win11DebloatSettings -Times 2 -Exactly
		Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq 'Debloating completed!' }
	}

	It "reports an error instead of success when Win11Debloat exits with a non-zero code" {
		$scriptPath = Join-Path $TestDrive 'Win11Debloat-Failing.ps1'
		Set-Content -Path $scriptPath -Value 'exit 3'

		$global:MachineSpecificPaths = @{
			Projects = @{ Self = @{ Root = $TestDrive } }
		}
		$global:Configuration = @{
			BootstrapConfig = @{ LocalScripts = @{ Win11Debloat = $scriptPath } }
		}

		Mock Test-Path { $true }

		Start-Win11Debloat

		Should -Invoke Write-LogError -ParameterFilter { $Message -eq 'Win11Debloat exited with code 3' }
		Should -Invoke Write-LogSuccess -Times 0
	}
}
