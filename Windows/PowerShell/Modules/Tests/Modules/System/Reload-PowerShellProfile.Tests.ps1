#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Reload-PowerShellProfile.ps1"

	function Invoke-ReloadPowerShellProfileWithProfile {
		param(
			[Parameter(Mandatory = $true)]
			$ProfileValue
		)

		& {
			param($InjectedProfile)
			Set-Variable -Name Profile -Scope Local -Value $InjectedProfile
			Reload-PowerShellProfile
		} -InjectedProfile $ProfileValue
	}
}

Describe "Reload-PowerShellProfile" {
	BeforeEach {
		$script:executedProfiles = @()
		$script:reloadedModules = $false

		Mock Write-Host { }
		Mock Reload-CustomModules {
			$script:reloadedModules = $true
		}
	}

	It "reloads custom modules and dot-sources all existing profile scripts" {
		$auah = Join-Path $TestDrive "AllUsersAllHosts.ps1"
		$auch = Join-Path $TestDrive "AllUsersCurrentHost.ps1"
		$cuah = Join-Path $TestDrive "CurrentUserAllHosts.ps1"
		$cuch = Join-Path $TestDrive "CurrentUserCurrentHost.ps1"

		Set-Content -Path $auah -Value '$script:executedProfiles += ''AllUsersAllHosts''' -Encoding utf8
		Set-Content -Path $auch -Value '$script:executedProfiles += ''AllUsersCurrentHost''' -Encoding utf8
		Set-Content -Path $cuah -Value '$script:executedProfiles += ''CurrentUserAllHosts''' -Encoding utf8
		Set-Content -Path $cuch -Value '$script:executedProfiles += ''CurrentUserCurrentHost''' -Encoding utf8

		$testProfile = [PSCustomObject]@{
			AllUsersAllHosts       = $auah
			AllUsersCurrentHost    = $auch
			CurrentUserAllHosts    = $cuah
			CurrentUserCurrentHost = $cuch
		}

		Invoke-ReloadPowerShellProfileWithProfile -ProfileValue $testProfile

		$script:reloadedModules | Should -BeTrue
		$script:executedProfiles.Count | Should -Be 4
		$script:executedProfiles | Should -Contain 'AllUsersAllHosts'
		$script:executedProfiles | Should -Contain 'AllUsersCurrentHost'
		$script:executedProfiles | Should -Contain 'CurrentUserAllHosts'
		$script:executedProfiles | Should -Contain 'CurrentUserCurrentHost'
	}

	It "only dot-sources profile scripts that exist" {
		$auah = Join-Path $TestDrive "AllUsersAllHosts.ps1"
		$cuah = Join-Path $TestDrive "CurrentUserAllHosts.ps1"

		Set-Content -Path $auah -Value '$script:executedProfiles += ''AllUsersAllHosts''' -Encoding utf8
		Set-Content -Path $cuah -Value '$script:executedProfiles += ''CurrentUserAllHosts''' -Encoding utf8

		$testProfile = [PSCustomObject]@{
			AllUsersAllHosts       = $auah
			AllUsersCurrentHost    = (Join-Path $TestDrive "Missing-AllUsersCurrentHost.ps1")
			CurrentUserAllHosts    = $cuah
			CurrentUserCurrentHost = (Join-Path $TestDrive "Missing-CurrentUserCurrentHost.ps1")
		}

		Invoke-ReloadPowerShellProfileWithProfile -ProfileValue $testProfile

		$script:reloadedModules | Should -BeTrue
		$script:executedProfiles.Count | Should -Be 2
		$script:executedProfiles | Should -Contain 'AllUsersAllHosts'
		$script:executedProfiles | Should -Contain 'CurrentUserAllHosts'
	}
}
