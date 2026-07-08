#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Get-TargetTerminalWindow.ps1"
}

Describe "Get-TargetTerminalWindow" {
	BeforeEach {
		$script:windows = @(
			[PSCustomObject]@{ Handle = [IntPtr]11; Title = "Terminal A" },
			[PSCustomObject]@{ Handle = [IntPtr]22; Title = "Terminal B" }
		)
		Mock Get-WindowHandle { $script:windows }
	}

	It "returns matched window when a specific handle is provided" {
		$result = Get-TargetTerminalWindow -TerminalWindowHandle ([IntPtr]22)

		$result.Handle | Should -Be ([IntPtr]22)
	}

	It "returns first window when no specific handle is provided" {
		$result = Get-TargetTerminalWindow

		$result.Handle | Should -Be ([IntPtr]11)
	}
}
