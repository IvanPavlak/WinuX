#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Get-BrowserTitlePattern.ps1"
}

Describe "Get-BrowserTitlePattern" {
	It "returns a pattern for every configured browser name" {
		foreach ($browser in @("Firefox", "Tor", "Chrome", "Edge", "Brave")) {
			Get-BrowserTitlePattern -BrowserName $browser | Should -Not -BeNullOrEmpty
		}
	}

	It "returns null for unknown browser names" {
		Get-BrowserTitlePattern -BrowserName "CustomBrowser" | Should -BeNullOrEmpty
	}

	It "matches the real Edge title, which embeds a zero-width space before ' Edge'" {
		# Regression test: Edge titles are "... - Microsoft<U+200B> Edge". The old
		# pattern "Microsoft.?Edge" allowed at most one character between the words
		# and never matched, so Kill-All left every Edge window open.
		$realEdgeTitle = "New tab - Personal - Microsoft$([char]0x200B) Edge"

		$realEdgeTitle -match (Get-BrowserTitlePattern -BrowserName "Edge") | Should -BeTrue
	}

	It "matches an Edge title with a plain space (ANSI-degraded or older titles)" {
		"New tab - Microsoft Edge" -match (Get-BrowserTitlePattern -BrowserName "Edge") | Should -BeTrue
	}

	It "distinguishes Tor Browser windows from Firefox windows" {
		$firefoxPattern = Get-BrowserTitlePattern -BrowserName "Firefox"
		$torPattern = Get-BrowserTitlePattern -BrowserName "Tor"

		"WinuX - Mozilla Firefox" -match $firefoxPattern | Should -BeTrue
		"WinuX - Mozilla Firefox" -match $torPattern | Should -BeFalse
		"Connect to Tor - Tor Browser" -match $torPattern | Should -BeTrue
		"Connect to Tor - Tor Browser" -match $firefoxPattern | Should -BeFalse
	}
}
