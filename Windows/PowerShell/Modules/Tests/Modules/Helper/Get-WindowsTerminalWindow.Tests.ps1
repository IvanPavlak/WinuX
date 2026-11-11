#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Get-WindowsTerminalWindow.ps1"

	function New-TestWindow {
		param([int]$Handle, [string]$Title)
		[PSCustomObject]@{ Handle = [IntPtr]$Handle; Title = $Title; ProcessName = 'WindowsTerminal'; ProcessId = 42 }
	}
}

Describe "Get-WindowsTerminalWindow" {
	It "asks for the windows of the WindowsTerminal process" {
		Mock Get-WindowHandle { @() }

		Get-WindowsTerminalWindow

		Should -Invoke Get-WindowHandle -Times 1 -Exactly -ParameterFilter { $ProcessName -eq 'WindowsTerminal' }
	}

	It "leaves out the PopupHost helper window, even when it comes first" {
		Mock Get-WindowHandle {
			@(
				(New-TestWindow -Handle 1 -Title 'PopupHost'),
				(New-TestWindow -Handle 2 -Title 'PowerShell'),
				(New-TestWindow -Handle 3 -Title 'Server.Api')
			)
		}

		$result = @(Get-WindowsTerminalWindow)

		$result.Handle | Should -Be @([IntPtr]2, [IntPtr]3)
		($result | Select-Object -First 1).Handle | Should -Be ([IntPtr]2)
	}

	It "keeps a terminal window whose title only contains or differs in case from PopupHost" {
		Mock Get-WindowHandle {
			@(
				(New-TestWindow -Handle 4 -Title 'PopupHost notes'),
				(New-TestWindow -Handle 5 -Title 'popuphost')
			)
		}

		@(Get-WindowsTerminalWindow).Handle | Should -Be @([IntPtr]4, [IntPtr]5)
	}

	It "returns nothing when only helper windows are open" {
		Mock Get-WindowHandle { @((New-TestWindow -Handle 1 -Title 'PopupHost')) }

		@(Get-WindowsTerminalWindow).Count | Should -Be 0
	}

	It "returns nothing when no Windows Terminal window is open" {
		Mock Get-WindowHandle { @() }

		@(Get-WindowsTerminalWindow).Count | Should -Be 0
	}
}
