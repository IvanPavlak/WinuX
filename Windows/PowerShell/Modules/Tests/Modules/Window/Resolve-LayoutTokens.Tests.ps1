#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Resolve-LayoutTokens.ps1"
}

Describe "Resolve-LayoutTokens" {
	BeforeEach {
		$script:LayoutTokenCache = $null
		$script:SavedConfiguration = $global:Configuration
	}

	AfterEach {
		$global:Configuration = $script:SavedConfiguration
	}

	It "expands Browser token from Universal.Browsers - the map the base configuration actually ships" {
		# This is the regression test for the lookup bug: the function used to read ONLY a
		# top-level Browsers key, which the base configuration never populates (the shipped map
		# lives at Universal.Browsers), so the preferred branch never fired on a stock setup.
		$global:Configuration = @{
			Universal = @{
				Browsers = @{
					Firefox = @{ Exe = "firefox.exe" }
					Vivaldi = @{ Exe = "vivaldi.exe" }
					Tor     = @{ Exe = "firefox.exe" }
				}
			}
		}
		$entry = @{ ProcessName = "Browser"; WindowTitle = "Browser"; Zone = "Left" }

		$result = Resolve-LayoutTokens -LayoutEntry $entry

		$result.ProcessName | Should -Match "firefox"
		$result.ProcessName | Should -Match "vivaldi"
		$result.WindowTitle | Should -Match "Firefox"
		$result.WindowTitle | Should -Match "Vivaldi"
		$result.WindowTitle | Should -Not -Match "Tor"
	}

	It "falls back to a legacy top-level Browsers map when Universal has none" {
		# The top-level key was the only location the old lookup honoured, so a fork may have
		# placed its map there as a workaround. It must keep working.
		$global:Configuration = @{
			Browsers = @{
				Firefox = @{ Exe = "firefox.exe" }
				Chrome  = @{ Exe = "chrome.exe" }
				Tor     = @{ Exe = "firefox.exe" }
			}
		}
		$entry = @{ ProcessName = "Browser"; WindowTitle = "Browser" }

		$result = Resolve-LayoutTokens -LayoutEntry $entry

		$result.ProcessName | Should -Match "firefox|chrome"
		$result.ProcessName | Should -Not -Match "tor"
		$result.WindowTitle | Should -Match "Firefox|Chrome"
	}

	It "prefers Universal.Browsers over a legacy top-level map when both exist" {
		$global:Configuration = @{
			Universal = @{
				Browsers = @{ Vivaldi = @{ Exe = "vivaldi.exe" } }
			}
			Browsers  = @{ Chrome = @{ Exe = "chrome.exe" } }
		}
		$entry = @{ ProcessName = "Browser" }

		$result = Resolve-LayoutTokens -LayoutEntry $entry

		$result.ProcessName | Should -Match "vivaldi"
		$result.ProcessName | Should -Not -Match "chrome"
	}

	It "uses the built-in browser set when no configuration is loaded" {
		$global:Configuration = $null
		$entry = @{ ProcessName = "Browser"; WindowTitle = "Browser" }

		$result = Resolve-LayoutTokens -LayoutEntry $entry

		$result.ProcessName | Should -Be "(firefox|chrome|msedge|brave)"
		$result.WindowTitle | Should -Match "Firefox"
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
