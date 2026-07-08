#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Add-PositionedWindow.ps1"
}

Describe "Add-PositionedWindow" {
	BeforeEach {
		Mock Write-Host { }
		Mock Write-LogDebug { }
	}

	It "initializes tracking collection and adds a window state" {
		$script:PositionedWindowHandles = $null

		Add-PositionedWindow -WindowHandle ([IntPtr]5) -ExpectedX 10 -ExpectedY 20 -ExpectedWidth 800 -ExpectedHeight 600 -WindowTitle "App"

		$script:PositionedWindowHandles.Count | Should -Be 1
		$script:PositionedWindowHandles[0].WindowTitle | Should -Be "App"
	}

	It "replaces existing state for the same handle" {
		$script:PositionedWindowHandles = [System.Collections.ArrayList]::new()
		$null = $script:PositionedWindowHandles.Add(@{
				Handle         = [IntPtr]7
				ExpectedX      = 1
				ExpectedY      = 2
				ExpectedWidth  = 300
				ExpectedHeight = 200
				WindowTitle    = "Old"
				DesktopNumber  = 0
			})

		Add-PositionedWindow -WindowHandle ([IntPtr]7) -ExpectedX 50 -ExpectedY 60 -ExpectedWidth 900 -ExpectedHeight 700 -WindowTitle "New"

		$script:PositionedWindowHandles.Count | Should -Be 1
		$script:PositionedWindowHandles[0].ExpectedX | Should -Be 50
		$script:PositionedWindowHandles[0].WindowTitle | Should -Be "New"
	}

	It "emits debug output when verbose logging is enabled" {
		$script:PositionedWindowHandles = [System.Collections.ArrayList]::new()

		Add-PositionedWindow -WindowHandle ([IntPtr]8) -ExpectedX 10 -ExpectedY 20 -ExpectedWidth 800 -ExpectedHeight 600 -WindowTitle "Dbg"

		Should -Invoke Write-LogDebug -Times 1
	}

	It "stores the process fingerprint when ExpectedProcessName and ExpectedProcessId are provided" {
		$script:PositionedWindowHandles = [System.Collections.ArrayList]::new()

		Add-PositionedWindow -WindowHandle ([IntPtr]9) -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "Fp" -ExpectedProcessName "chrome" -ExpectedProcessId ([uint32]4242)

		$script:PositionedWindowHandles[0].ProcessName | Should -Be "chrome"
		$script:PositionedWindowHandles[0].ProcessId | Should -Be ([uint32]4242)
	}

	It "defaults the process fingerprint to empty values when omitted" {
		$script:PositionedWindowHandles = [System.Collections.ArrayList]::new()

		Add-PositionedWindow -WindowHandle ([IntPtr]10) -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "NoFp"

		$script:PositionedWindowHandles[0].ProcessName | Should -BeNullOrEmpty
		$script:PositionedWindowHandles[0].ProcessId | Should -Be ([uint32]0)
	}

	It "preserves the updated fingerprint when replacing an existing handle" {
		$script:PositionedWindowHandles = [System.Collections.ArrayList]::new()
		$null = $script:PositionedWindowHandles.Add(@{
				Handle      = [IntPtr]11
				WindowTitle = "Old"
				ProcessName = "old"
				ProcessId   = [uint32]1
			})

		Add-PositionedWindow -WindowHandle ([IntPtr]11) -ExpectedX 0 -ExpectedY 0 -ExpectedWidth 100 -ExpectedHeight 100 -WindowTitle "New" -ExpectedProcessName "new" -ExpectedProcessId ([uint32]99)

		$script:PositionedWindowHandles.Count | Should -Be 1
		$script:PositionedWindowHandles[0].ProcessName | Should -Be "new"
		$script:PositionedWindowHandles[0].ProcessId | Should -Be ([uint32]99)
	}
}
