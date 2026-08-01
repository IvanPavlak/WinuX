#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Start-Win11Debloat.ps1"
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
		Mock Remove-Item { }
		Mock New-Item { }
		Mock Get-Item {
			[PSCustomObject]@{ LinkType = 'SymbolicLink'; Target = @('') }
		}
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

		# Win11Debloat reads saved settings from the repo's LastUsedSettings.json (via a Config symlink).
		$savedSettingsDir = Join-Path $TestDrive 'Windows\Win11Debloat'
		[System.IO.Directory]::CreateDirectory($savedSettingsDir) | Out-Null
		$savedSettingsTarget = Join-Path $savedSettingsDir 'LastUsedSettings.json'
		Set-Content -Path $savedSettingsTarget -Value '{ "Version": "1.0", "Settings": [] }'

		$global:MachineSpecificPaths = @{
			Projects = @{ Self = @{ Root = $TestDrive } }
		}
		$global:Configuration = @{
			BootstrapConfig = @{ LocalScripts = @{ Win11Debloat = $scriptPath } }
		}

		Mock Test-Path { $true }
		Mock Get-Item {
			[PSCustomObject]@{ LinkType = 'SymbolicLink'; Target = @($savedSettingsTarget) }
		}

		Start-Win11Debloat

		Get-Content -LiteralPath $invocationPath | Should -Be @('Desktop', 'True', 'True')
		Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq 'Debloating with saved settings completed!' }
	}

	It "reports an error instead of success when Win11Debloat exits with a non-zero code" {
		$scriptPath = Join-Path $TestDrive 'Win11Debloat-Failing.ps1'
		Set-Content -Path $scriptPath -Value 'exit 3'

		$savedSettingsDir = Join-Path $TestDrive 'Windows\Win11Debloat'
		[System.IO.Directory]::CreateDirectory($savedSettingsDir) | Out-Null
		$savedSettingsTarget = Join-Path $savedSettingsDir 'LastUsedSettings.json'
		Set-Content -Path $savedSettingsTarget -Value '{ "Version": "1.0", "Settings": [] }'

		$global:MachineSpecificPaths = @{
			Projects = @{ Self = @{ Root = $TestDrive } }
		}
		$global:Configuration = @{
			BootstrapConfig = @{ LocalScripts = @{ Win11Debloat = $scriptPath } }
		}

		Mock Test-Path { $true }
		Mock Get-Item {
			[PSCustomObject]@{ LinkType = 'SymbolicLink'; Target = @($savedSettingsTarget) }
		}

		Start-Win11Debloat

		Should -Invoke Write-LogError -ParameterFilter { $Message -eq 'Win11Debloat exited with code 3' }
		Should -Invoke Write-LogSuccess -Times 0
	}
}
