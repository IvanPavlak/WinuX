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

	It "runs script with -RunSavedSettings when a non-empty saved-settings file exists" {
		$scriptPath = Join-Path $TestDrive 'Win11Debloat.ps1'
		$scriptContent = @'
param([switch]$RunSavedSettings,[switch]$Silent)
$global:Win11DebloatCalled = @($RunSavedSettings.IsPresent, $Silent.IsPresent)
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

		$global:Win11DebloatCalled = $null
		Start-Win11Debloat

		$global:Win11DebloatCalled | Should -Be @($true, $true)
	}
}
