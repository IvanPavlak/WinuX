#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Select-WindowsTerminalTab.ps1"
}

Describe "Select-WindowsTerminalTab" {
	It "returns `$false for a zero handle" {
		Select-WindowsTerminalTab -WindowHandle ([IntPtr]::Zero) -TabTitle "Anything" | Should -BeFalse
	}

	It "returns `$false when neither a title nor an index names a tab" {
		Select-WindowsTerminalTab -WindowHandle ([IntPtr]0x7FFFFFFF) | Should -BeFalse
	}

	It "returns `$false when the handle is not a live automation element" {
		# The caller falls back to its legacy path on `$false - a bogus handle must never throw.
		Select-WindowsTerminalTab -WindowHandle ([IntPtr]0x7FFFFFFF) -TabTitle "Anything" | Should -BeFalse
	}

	It "returns `$false when no tab with the given title exists (never selects a different tab)" {
		$wtWindow = [WindowModule.Native]::GetAllWindows() |
			Where-Object { $_.ProcessName -eq 'WindowsTerminal' } |
			Select-Object -First 1

		if (-not $wtWindow) {
			Set-ItResult -Skipped -Because "no Windows Terminal window available in this session"
			return
		}

		$result = Select-WindowsTerminalTab -WindowHandle $wtWindow.Handle -TabTitle ("NoSuchTab_" + [guid]::NewGuid()) -TabIndex 999

		$result | Should -BeFalse
	}
}
