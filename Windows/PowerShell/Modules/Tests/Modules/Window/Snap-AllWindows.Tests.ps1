#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Snap-AllWindows.ps1"

	# The pre-snap inset source, stubbed so Mock can attach in a dot-sourced unit and so these
	# cases never read the live session configuration. It has its own suite.
	function Get-WindowInsetPercent { }
}

Describe "Snap-AllWindows" {
	BeforeEach {
		Mock Get-WindowInsetPercent { 0.05 }
		Mock Ensure-WindowsFormsLoaded { }
		Mock Start-FancyZones { $true }
		Mock Get-PositionedWindowCount { 0 }
		Mock Reset-KeyboardModifiers { @() }
		Mock Write-Host { }
	}

	It "returns when no positioned windows are tracked" {
		$result = Snap-AllWindows

		$result | Should -BeNullOrEmpty
		Should -Invoke Start-FancyZones -Times 1
		Should -Invoke Get-PositionedWindowCount -Times 1
	}
}
