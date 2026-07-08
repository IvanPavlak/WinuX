#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Window\Window.psm1"
	Import-Module $ModulePath -Force
}

Describe "Get-WindowHandle" {
	BeforeAll {
		# Mock window data representing a typical desktop state
		$script:MockWindows = @(
			[PSCustomObject]@{ Handle = 1001; Title = "file.ps1 - Visual Studio Code"; ProcessName = "Code"; ProcessId = 100 }
			[PSCustomObject]@{ Handle = 1002; Title = "YouTube - Mozilla Firefox"; ProcessName = "firefox"; ProcessId = 200 }
			[PSCustomObject]@{ Handle = 1003; Title = "Gmail - Inbox - Mozilla Firefox"; ProcessName = "firefox"; ProcessId = 201 }
			[PSCustomObject]@{ Handle = 1004; Title = ""; ProcessName = "explorer"; ProcessId = 300 }
			[PSCustomObject]@{ Handle = 1005; Title = "My Document - Word"; ProcessName = "WINWORD"; ProcessId = 400 }
			[PSCustomObject]@{ Handle = 1006; Title = "Chrome - New Tab"; ProcessName = "chrome"; ProcessId = 500 }
			[PSCustomObject]@{ Handle = 1007; Title = "Notepad"; ProcessName = "notepad"; ProcessId = 600 }
			[PSCustomObject]@{ Handle = 1008; Title = "notes.txt - Editor Plus Plus"; ProcessName = "notepad++"; ProcessId = 700 }
		)
	}

	BeforeEach {
		Mock Get-CachedWindows { $script:MockWindows } -ModuleName Window
		Mock Write-Error { } -ModuleName Window
	}

	Context "Filtering by ProcessName" {
		It "Should return windows matching exact process name" {
			$result = @(Get-WindowHandle -ProcessName "firefox")

			$result.Count | Should -Be 2
			$result[0].ProcessName | Should -Be "firefox"
			$result[1].ProcessName | Should -Be "firefox"
		}

		It "Should return empty for non-existent process" {
			$result = @(Get-WindowHandle -ProcessName "nonexistent")

			$result.Count | Should -Be 0
		}

		It "Should match case-insensitively (PowerShell -eq default)" {
			$result = @(Get-WindowHandle -ProcessName "Firefox")

			$result.Count | Should -Be 2
		}

		It "Should treat literal process names with plus signs as exact matches" {
			$result = @(Get-WindowHandle -ProcessName "notepad++")

			$result.Count | Should -Be 1
			$result[0].ProcessName | Should -Be "notepad++"
		}
	}

	Context "Filtering by WindowTitle" {
		It "Should match wildcard pattern *YouTube*" {
			$result = @(Get-WindowHandle -WindowTitle "*YouTube*")

			$result.Count | Should -Be 1
			$result[0].Title | Should -BeLike "*YouTube*"
		}

		It "Should match regex pattern" {
			$result = @(Get-WindowHandle -WindowTitle "^Chrome")

			$result.Count | Should -Be 1
			$result[0].ProcessName | Should -Be "chrome"
		}

		It "Should match case-insensitive regex with (?i)" {
			$result = @(Get-WindowHandle -WindowTitle "(?i)notepad")

			$result.Count | Should -Be 1
			$result[0].ProcessName | Should -Be "notepad"
		}

		It "Should skip windows with empty titles" {
			$result = @(Get-WindowHandle -WindowTitle "*explorer*")

			$result.Count | Should -Be 0
		}

		It "Should return empty for non-matching pattern" {
			$result = @(Get-WindowHandle -WindowTitle "*Slack*")

			$result.Count | Should -Be 0
		}
	}

	Context "Combined ProcessName and WindowTitle (OR logic)" {
		It "Should match by either ProcessName or WindowTitle" {
			# ProcessName=Code matches 1 window, WindowTitle=*Gmail* matches 1 different window
			$result = @(Get-WindowHandle -ProcessName "Code" -WindowTitle "*Gmail*")

			$result.Count | Should -Be 2
		}

		It "Should include all matches when both match overlapping windows" {
			# ProcessName=firefox matches 2, WindowTitle=*YouTube* also matches 1 of those
			$result = @(Get-WindowHandle -ProcessName "firefox" -WindowTitle "*YouTube*")

			# OR logic returns unique entries: both firefox windows match (one by name, one by both)
			$result.Count | Should -Be 2
		}
	}

	Context "No filters (All)" {
		It "Should return all windows" {
			$result = @(Get-WindowHandle)

			$result.Count | Should -Be 8
		}
	}
}
