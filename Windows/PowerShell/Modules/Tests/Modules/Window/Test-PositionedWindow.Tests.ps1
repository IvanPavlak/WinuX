#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Test-PositionedWindow.ps1"
}

Describe "Test-PositionedWindow" {
	It "returns false when tracking collection is not initialized" {
		$script:PositionedWindowHandles = $null

		$result = Test-PositionedWindow -WindowHandle ([IntPtr]3)

		$result | Should -BeFalse
	}

	It "returns true when handle exists in tracking collection" {
		$script:PositionedWindowHandles = [System.Collections.ArrayList]::new()
		$null = $script:PositionedWindowHandles.Add(@{ Handle = [IntPtr]3 })

		$result = Test-PositionedWindow -WindowHandle ([IntPtr]3)

		$result | Should -BeTrue
	}

	It "returns false when handle is not tracked" {
		$script:PositionedWindowHandles = [System.Collections.ArrayList]::new()
		$null = $script:PositionedWindowHandles.Add(@{ Handle = [IntPtr]3 })

		$result = Test-PositionedWindow -WindowHandle ([IntPtr]99)

		$result | Should -BeFalse
	}
}
