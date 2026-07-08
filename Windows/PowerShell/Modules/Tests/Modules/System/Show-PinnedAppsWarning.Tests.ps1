#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Show-PinnedAppsWarning.ps1"
}

Describe "Show-PinnedAppsWarning" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogWarning { }
	}

	It "writes warning lines for each pinned app" {
		Show-PinnedAppsWarning -PinnedApps @("git", "nodejs")

		Should -Invoke Write-LogWarning -Times 1
		Should -Invoke Write-Host -Times 3
	}

	It "writes nothing when pinned app list is empty" {
		Show-PinnedAppsWarning -PinnedApps @()

		Should -Invoke Write-LogWarning -Times 0
		Should -Invoke Write-Host -Times 0
	}
}
