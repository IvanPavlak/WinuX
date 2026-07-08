#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Initialize-PositionedWindowTracking.ps1"
}

Describe "Initialize-PositionedWindowTracking" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogDebug { }
	}

	It "handles missing tracking collection without throwing" {
		$script:PositionedWindowHandles = $null

		{ Initialize-PositionedWindowTracking } | Should -Not -Throw
	}

	It "clears existing tracking collection" {
		$script:PositionedWindowHandles = [System.Collections.ArrayList]::new()
		$null = $script:PositionedWindowHandles.Add(@{ Handle = [IntPtr]9 })

		Initialize-PositionedWindowTracking

		$script:PositionedWindowHandles.Count | Should -Be 0
	}

	It "writes debug output when verbose logging is enabled" {
		$script:PositionedWindowHandles = $null

		Initialize-PositionedWindowTracking

		Should -Invoke Write-LogDebug -Times 1
	}
}
