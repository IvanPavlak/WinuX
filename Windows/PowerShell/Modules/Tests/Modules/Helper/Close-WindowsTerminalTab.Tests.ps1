#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Close-WindowsTerminalTab.ps1"
}

Describe "Close-WindowsTerminalTab" {
	It "returns `$false for a zero handle" {
		Close-WindowsTerminalTab -WindowHandle ([IntPtr]::Zero) -TabTitle "Anything" | Should -BeFalse
	}

	It "returns `$false when the handle is not a live automation element" {
		# The caller uses `$false to fall back to the legacy Ctrl+W path - a bogus handle
		# must never throw.
		Close-WindowsTerminalTab -WindowHandle ([IntPtr]0x7FFFFFFF) -TabTitle "Anything" | Should -BeFalse
	}

	It "returns `$false when no tab with the given title exists (never closes a different tab)" {
		$wtWindow = [WindowModule.Native]::GetAllWindows() |
			Where-Object { $_.ProcessName -eq 'WindowsTerminal' } |
			Select-Object -First 1

		if (-not $wtWindow) {
			Set-ItResult -Skipped -Because "no Windows Terminal window available in this session"
			return
		}

		$result = Close-WindowsTerminalTab -WindowHandle $wtWindow.Handle -TabTitle ("NoSuchTab_" + [guid]::NewGuid())

		$result | Should -BeFalse
	}
}
