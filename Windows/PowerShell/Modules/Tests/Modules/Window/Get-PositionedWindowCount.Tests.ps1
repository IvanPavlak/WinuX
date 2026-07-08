#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-PositionedWindowCount.ps1"
}

Describe "Get-PositionedWindowCount" {
	It "returns 0 when tracking collection is not initialized" {
		$script:PositionedWindowHandles = $null

		$result = Get-PositionedWindowCount

		$result | Should -Be 0
	}

	It "returns current tracking count when collection exists" {
		$script:PositionedWindowHandles = [System.Collections.ArrayList]::new()
		$null = $script:PositionedWindowHandles.Add(@{ Handle = [IntPtr]1 })
		$null = $script:PositionedWindowHandles.Add(@{ Handle = [IntPtr]2 })

		$result = Get-PositionedWindowCount

		$result | Should -Be 2
	}
}
