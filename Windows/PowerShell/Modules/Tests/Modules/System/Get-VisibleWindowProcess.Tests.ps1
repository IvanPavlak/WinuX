#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Get-VisibleWindowProcess.ps1"

	# The Window module's enumeration pair. Stubbed so Mock can attach whether or not the
	# module is loaded; every test below replaces them, none touches the real desktop.
	if (-not (Get-Command Get-CachedWindows -ErrorAction SilentlyContinue)) {
		function Get-CachedWindows { @() }
	}
	if (-not (Get-Command Clear-WindowCache -ErrorAction SilentlyContinue)) {
		function Clear-WindowCache { }
	}

	function New-TestWindow {
		param([int]$Handle, [string]$Title, [string]$ProcessName, [int]$ProcessId, [int]$Width = 800, [int]$Height = 600)
		[PSCustomObject]@{
			Handle = [IntPtr]$Handle; Title = $Title; ProcessName = $ProcessName; ProcessId = $ProcessId
			Left = 0; Top = 0; Width = $Width; Height = $Height
		}
	}
}

Describe "Get-VisibleWindowProcess" {
	BeforeEach {
		Mock Clear-WindowCache { }
		Mock Get-CachedWindows { @() }
		Mock Get-Process { @() }
	}

	It "groups visible titled windows by owning process" {
		Mock Get-CachedWindows {
			@(
				(New-TestWindow -Handle 1 -Title 'Inbox - Mozilla Firefox' -ProcessName 'firefox' -ProcessId 100),
				(New-TestWindow -Handle 2 -Title 'Docs - Mozilla Firefox' -ProcessName 'firefox' -ProcessId 100),
				(New-TestWindow -Handle 3 -Title 'Untitled - Notepad' -ProcessName 'Notepad' -ProcessId 200)
			)
		}

		$result = @(Get-VisibleWindowProcess)

		$result.Count | Should -Be 2
		$firefox = $result | Where-Object Id -EQ 100
		$firefox.ProcessName | Should -Be 'firefox'
		@($firefox.WindowTitles).Count | Should -Be 2
		$firefox.MainWindowTitle | Should -Be 'Inbox - Mozilla Firefox'
		$firefox.Source | Should -Be 'EnumWindows'
		Should -Invoke Clear-WindowCache -Times 1 -Exactly
	}

	It "finds a process whose .NET main window is untitled, as long as one of its windows is titled" {
		# Only the titled window is enumerated (GetAllWindows skips untitled ones); the process
		# still counts. Get-Process is not consulted at all on this path.
		Mock Get-CachedWindows {
			@((New-TestWindow -Handle 4 -Title 'Claude' -ProcessName 'claude' -ProcessId 300))
		}

		$result = @(Get-VisibleWindowProcess)

		$result.Count | Should -Be 1
		$result[0].Id | Should -Be 300
		Should -Invoke Get-Process -Times 0
	}

	It "ignores shell windows and shell processes" {
		Mock Get-CachedWindows {
			@(
				(New-TestWindow -Handle 5 -Title 'Program Manager' -ProcessName 'explorer' -ProcessId 400),
				(New-TestWindow -Handle 6 -Title 'Windows Input Experience' -ProcessName 'TextInputHost' -ProcessId 401),
				(New-TestWindow -Handle 7 -Title 'Calculator' -ProcessName 'ApplicationFrameHost' -ProcessId 402),
				(New-TestWindow -Handle 8 -Title 'Calculator' -ProcessName 'CalculatorApp' -ProcessId 403),
				(New-TestWindow -Handle 9 -Title 'Downloads' -ProcessName 'explorer' -ProcessId 400)
			)
		}

		$result = @(Get-VisibleWindowProcess)

		# The packaged app itself is a candidate; its frame host and the shell are not.
		$result.Count | Should -Be 1
		$result[0].ProcessName | Should -Be 'CalculatorApp'
	}

	It "ignores windows with no meaningful size or no title" {
		Mock Get-CachedWindows {
			@(
				(New-TestWindow -Handle 10 -Title 'Ghost' -ProcessName 'ghost' -ProcessId 500 -Width 0 -Height 0),
				(New-TestWindow -Handle 11 -Title '' -ProcessName 'silent' -ProcessId 501),
				(New-TestWindow -Handle 12 -Title 'Real' -ProcessName 'real' -ProcessId 502)
			)
		}

		$result = @(Get-VisibleWindowProcess)

		$result.Count | Should -Be 1
		$result[0].ProcessName | Should -Be 'real'
	}

	It "returns nothing when no application window is visible" {
		Mock Get-CachedWindows { @() }

		@(Get-VisibleWindowProcess).Count | Should -Be 0
	}

	Context "without the Window module" {
		BeforeEach {
			# Make the module look absent for the duration of the test.
			Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-CachedWindows' -or $Name -eq 'Clear-WindowCache' }
		}

		It "falls back to Get-Process and MainWindowTitle" {
			Mock Get-Process {
				@(
					[PSCustomObject]@{ ProcessName = 'notepad'; Id = 600; MainWindowTitle = 'Untitled - Notepad' },
					[PSCustomObject]@{ ProcessName = 'svchost'; Id = 601; MainWindowTitle = '' },
					[PSCustomObject]@{ ProcessName = 'explorer'; Id = 602; MainWindowTitle = 'Program Manager' }
				)
			}

			$result = @(Get-VisibleWindowProcess)

			$result.Count | Should -Be 1
			$result[0].Id | Should -Be 600
			$result[0].MainWindowTitle | Should -Be 'Untitled - Notepad'
			$result[0].Source | Should -Be 'MainWindowTitle'
			Should -Invoke Get-CachedWindows -Times 0
		}
	}
}
