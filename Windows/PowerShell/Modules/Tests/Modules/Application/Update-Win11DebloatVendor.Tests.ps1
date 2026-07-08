#Requires -Modules Pester

BeforeAll {
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths

	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Update-Win11DebloatVendor.ps1"
}

AfterAll {
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
}

Describe "Update-Win11DebloatVendor" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogError { }
	}

	It "returns early when updater script is missing" {
		$global:MachineSpecificPaths = @{ Projects = @{ Self = @{ Root = 'C:\Repo\WinuX' } } }
		Mock Test-Path { $false }

		Update-Win11DebloatVendor

		Should -Invoke Write-LogError -Times 1 -Exactly
	}

	It "invokes updater script with bound parameters when updater path exists" {
		$repoRoot = Join-Path $TestDrive 'WinuX'
		$updaterDir = Join-Path $repoRoot 'Windows\Win11Debloat'
		New-Item -ItemType Directory -Path $updaterDir -Force | Out-Null
		$updaterPath = Join-Path $updaterDir 'Update-Win11DebloatVendor.ps1'

		$scriptContent = @'
param([string]$ReleaseTag,[string]$Repository)
$global:Win11DebloatVendorCalled = @($ReleaseTag, $Repository)
'@
		Set-Content -Path $updaterPath -Value $scriptContent

		$global:MachineSpecificPaths = @{ Projects = @{ Self = @{ Root = $repoRoot } } }
		Mock Test-Path { $true }

		$global:Win11DebloatVendorCalled = $null
		Update-Win11DebloatVendor -ReleaseTag '2026.05.11' -Repository 'Raphire/Win11Debloat'

		$global:Win11DebloatVendorCalled | Should -Be @('2026.05.11', 'Raphire/Win11Debloat')
	}
}
