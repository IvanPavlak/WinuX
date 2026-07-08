#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Resolve-PositionedWindowHandle.ps1"

	# Get-CachedWindows is a sibling helper; stub it so it can be mocked per-test.
	function Get-CachedWindows { }
}

Describe "Resolve-PositionedWindowHandle" {
	It "enumerates the window list only once" {
		Mock Get-CachedWindows {
			@(
				[PSCustomObject]@{ Handle = [IntPtr]100; ProcessId = 10; ProcessName = "chrome"; Title = "App" }
			)
		}

		$state = @{ WindowTitle = "App"; ProcessName = "chrome"; ProcessId = [uint32]10 }
		$null = Resolve-PositionedWindowHandle -WindowState $state

		Should -Invoke Get-CachedWindows -Times 1 -Exactly
	}

	It "resolves a fresh handle by title when no process fingerprint is tracked" {
		Mock Get-CachedWindows {
			@(
				[PSCustomObject]@{ Handle = [IntPtr]100; ProcessId = 10; ProcessName = "chrome"; Title = "App" }
				[PSCustomObject]@{ Handle = [IntPtr]101; ProcessId = 11; ProcessName = "code"; Title = "Other" }
			)
		}

		$state = @{ WindowTitle = "App"; ProcessName = ""; ProcessId = [uint32]0 }
		$result = Resolve-PositionedWindowHandle -WindowState $state

		$result.Handle | Should -Be ([IntPtr]100)
	}

	It "matches the tracked title as a literal substring" {
		Mock Get-CachedWindows {
			@(
				[PSCustomObject]@{ Handle = [IntPtr]110; ProcessId = 12; ProcessName = "code"; Title = "main.ps1 - Visual Studio Code" }
			)
		}

		$state = @{ WindowTitle = "Visual Studio Code"; ProcessName = ""; ProcessId = [uint32]0 }
		$result = Resolve-PositionedWindowHandle -WindowState $state

		$result.Handle | Should -Be ([IntPtr]110)
	}

	It "intersects title and process matches (AND logic)" {
		Mock Get-CachedWindows {
			@(
				[PSCustomObject]@{ Handle = [IntPtr]200; ProcessId = 20; ProcessName = "firefox"; Title = "Shared" }
				[PSCustomObject]@{ Handle = [IntPtr]201; ProcessId = 21; ProcessName = "chrome"; Title = "Shared" }
			)
		}

		$state = @{ WindowTitle = "Shared"; ProcessName = "chrome"; ProcessId = [uint32]0 }
		$result = Resolve-PositionedWindowHandle -WindowState $state

		# Only handle 201 matches both the title and the process name.
		$result.Handle | Should -Be ([IntPtr]201)
	}

	It "filters candidates by process id when a fingerprint is tracked" {
		Mock Get-CachedWindows {
			@(
				[PSCustomObject]@{ Handle = [IntPtr]400; ProcessId = 40; ProcessName = "chrome"; Title = "App" }
				[PSCustomObject]@{ Handle = [IntPtr]401; ProcessId = 41; ProcessName = "chrome"; Title = "App" }
			)
		}

		$state = @{ WindowTitle = "App"; ProcessName = ""; ProcessId = [uint32]41 }
		$result = Resolve-PositionedWindowHandle -WindowState $state

		$result.Handle | Should -Be ([IntPtr]401)
	}

	It "returns null when no candidate matches the tracked process id" {
		Mock Get-CachedWindows {
			@(
				[PSCustomObject]@{ Handle = [IntPtr]500; ProcessId = 50; ProcessName = "chrome"; Title = "App" }
			)
		}

		$state = @{ WindowTitle = "App"; ProcessName = ""; ProcessId = [uint32]999 }
		$result = Resolve-PositionedWindowHandle -WindowState $state

		$result | Should -BeNullOrEmpty
	}

	It "returns null when the tracked title matches no live window" {
		Mock Get-CachedWindows {
			@(
				[PSCustomObject]@{ Handle = [IntPtr]600; ProcessId = 60; ProcessName = "chrome"; Title = "Something Else" }
			)
		}

		$state = @{ WindowTitle = "Missing"; ProcessName = ""; ProcessId = [uint32]0 }
		$result = Resolve-PositionedWindowHandle -WindowState $state

		$result | Should -BeNullOrEmpty
	}

	It "treats regex metacharacters in the tracked title literally" {
		Mock Get-CachedWindows {
			@(
				[PSCustomObject]@{ Handle = [IntPtr]700; ProcessId = 70; ProcessName = "msbuild"; Title = "Build (Debug) [x64]" }
				[PSCustomObject]@{ Handle = [IntPtr]701; ProcessId = 71; ProcessName = "other"; Title = "Build xDebugx x6x4x" }
			)
		}

		$state = @{ WindowTitle = "Build (Debug) [x64]"; ProcessName = ""; ProcessId = [uint32]0 }
		$result = Resolve-PositionedWindowHandle -WindowState $state

		# The metacharacter-laden title must match only the literal window, not a regex interpretation.
		$result.Handle | Should -Be ([IntPtr]700)
	}
}
