#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Resolve-LayoutTokens.ps1"
}

Describe "Resolve-LayoutTokens" {
	BeforeEach {
		$script:LayoutTokenCache = $null
	}

	It "expands Browser token for process and title fields" {
		$global:Configuration = @{
			Browsers = @{
				Firefox = @{ Exe = "firefox.exe" }
				Chrome  = @{ Exe = "chrome.exe" }
				Tor     = @{ Exe = "firefox.exe" }
			}
		}
		$entry = @{ ProcessName = "Browser"; WindowTitle = "Browser"; Zone = "Left" }

		$result = Resolve-LayoutTokens -LayoutEntry $entry

		$result.ProcessName | Should -Match "firefox|chrome"
		$result.ProcessName | Should -Not -Match "tor"
		$result.WindowTitle | Should -Match "Firefox|Chrome"
	}

	It "does not mutate input hashtable" {
		$entry = @{ ProcessName = "Browser"; WindowTitle = "Browser" }

		$null = Resolve-LayoutTokens -LayoutEntry $entry

		$entry.ProcessName | Should -Be "Browser"
		$entry.WindowTitle | Should -Be "Browser"
	}

	It "leaves non-token fields unchanged" {
		$entry = @{ ProcessName = "code"; WindowTitle = "Visual Studio Code" }

		$result = Resolve-LayoutTokens -LayoutEntry $entry

		$result.ProcessName | Should -Be "code"
		$result.WindowTitle | Should -Be "Visual Studio Code"
	}
}
