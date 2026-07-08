#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Snap-AllWindows.ps1"
}

Describe "Snap-AllWindows" {
	BeforeEach {
		Mock Ensure-WindowsFormsLoaded { }
		Mock Start-FancyZones { $true }
		Mock Get-PositionedWindowCount { 0 }
		Mock Write-Host { }
	}

	It "returns when no positioned windows are tracked" {
		$result = Snap-AllWindows

		$result | Should -BeNullOrEmpty
		Should -Invoke Start-FancyZones -Times 1
		Should -Invoke Get-PositionedWindowCount -Times 1
	}
}
