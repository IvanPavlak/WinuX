#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. "$ModuleRoot\System\Functions\Get-ConsoleWindowSize.ps1"

	# Whether this host has a console window at all. A headless CI runner or an IDE host throws
	# on the property read, which is the documented behaviour, so the suite asserts either way.
	$script:HasConsole = $true
	try { [void][Console]::WindowWidth } catch { $script:HasConsole = $false }
}

Describe "Get-ConsoleWindowSize" {
	It "returns Width and Height as integers matching the live console when a console is present" {
		if (-not $script:HasConsole) { Set-ItResult -Skipped -Because "this host has no console window"; return }

		$size = Get-ConsoleWindowSize

		$size.Width | Should -BeOfType [int]
		$size.Height | Should -BeOfType [int]
		$size.Width | Should -Be ([Console]::WindowWidth)
		$size.Height | Should -Be ([Console]::WindowHeight)
	}

	It "returns a fresh object on every call rather than a cached one" {
		if (-not $script:HasConsole) { Set-ItResult -Skipped -Because "this host has no console window"; return }

		$first = Get-ConsoleWindowSize
		$second = Get-ConsoleWindowSize

		[object]::ReferenceEquals($first, $second) | Should -BeFalse
		$first.Width | Should -Be $second.Width
	}

	It "throws rather than returning a placeholder when the host has no console window" {
		if ($script:HasConsole) { Set-ItResult -Skipped -Because "this host has a console window"; return }

		{ Get-ConsoleWindowSize } | Should -Throw
	}

	It "exposes exactly the two properties callers compare" {
		if (-not $script:HasConsole) { Set-ItResult -Skipped -Because "this host has no console window"; return }

		$names = (Get-ConsoleWindowSize).PSObject.Properties.Name | Sort-Object
		$names | Should -Be @("Height", "Width")
	}
}
