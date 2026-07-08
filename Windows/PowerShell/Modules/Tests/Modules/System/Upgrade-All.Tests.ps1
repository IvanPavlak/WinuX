#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Upgrade-All.ps1"
}

Describe "Upgrade-All" {
	BeforeEach {
		$global:Configuration = [PSCustomObject]@{
			PackageManagers = @()
		}

		Mock Test-AdminPrivileges { }
		Mock Get-PinnedApps { @() }
		Mock Show-PinnedAppsWarning { }
		Mock Write-Host { }
	}

	It "does nothing when no package managers are configured" {
		{ Upgrade-All } | Should -Not -Throw

		Should -Invoke Test-AdminPrivileges -Times 1
		Should -Invoke Get-PinnedApps -Times 0
	}
}
