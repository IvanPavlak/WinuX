#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Test-WindowTitleMatch.ps1"
}

Describe "Test-WindowTitleMatch" {
	Context "Exact process name matching" {
		It "Should match by exact process name (case-insensitive)" {
			$result = Test-WindowTitleMatch -ProcessName "Code" -WindowTitle "file.ps1 - Visual Studio Code" -Patterns @("Code")
			$result | Should -BeTrue
		}

		It "Should not match if process name doesn't match exactly" {
			$result = Test-WindowTitleMatch -ProcessName "Code" -WindowTitle "file.ps1" -Patterns @("VSCode")
			$result | Should -BeFalse
		}

		It "Should match process name even if window title is empty" {
			$result = Test-WindowTitleMatch -ProcessName "firefox" -WindowTitle "" -Patterns @("firefox")
			$result | Should -BeTrue
		}
	}

	Context "Wildcard pattern matching" {
		It "Should match wildcard pattern *YouTube*" {
			$result = Test-WindowTitleMatch -WindowTitle "YouTube - Google Chrome" -Patterns @("*YouTube*")
			$result | Should -BeTrue
		}

		It "Should match wildcard at the end: Chrome - *" {
			$result = Test-WindowTitleMatch -WindowTitle "Chrome - New Tab" -Patterns @("Chrome - *")
			$result | Should -BeTrue
		}

		It "Should not match when wildcard doesn't match" {
			$result = Test-WindowTitleMatch -WindowTitle "My Document - Word" -Patterns @("*YouTube*")
			$result | Should -BeFalse
		}
	}

	Context "Regex pattern matching" {
		It "Should match regex pattern" {
			$result = Test-WindowTitleMatch -WindowTitle "Gmail Inbox" -Patterns @("(.*Gmail.*|.*Inbox.*)")
			$result | Should -BeTrue
		}

		It "Should match case-insensitive regex with (?i)" {
			$result = Test-WindowTitleMatch -WindowTitle "NOTEPAD" -Patterns @("(?i)notepad")
			$result | Should -BeTrue
		}

		It "Should match regex anchor ^" {
			$result = Test-WindowTitleMatch -WindowTitle "Chrome - Tab 1" -Patterns @("^Chrome")
			$result | Should -BeTrue
		}

		It "Should not match regex anchor ^ when it doesn't start with pattern" {
			$result = Test-WindowTitleMatch -WindowTitle "Google Chrome" -Patterns @("^Chrome")
			$result | Should -BeFalse
		}
	}

	Context "Multiple patterns" {
		It "Should return true if any pattern matches" {
			$result = Test-WindowTitleMatch -WindowTitle "YouTube - Music" -Patterns @("*Gmail*", "*YouTube*", "*Outlook*")
			$result | Should -BeTrue
		}

		It "Should return false if no pattern matches" {
			$result = Test-WindowTitleMatch -WindowTitle "My Document - Word" -Patterns @("*YouTube*", "*Gmail*")
			$result | Should -BeFalse
		}
	}

	Context "Edge cases" {
		It "Should skip whitespace-only patterns" {
			$result = Test-WindowTitleMatch -WindowTitle "YouTube" -Patterns @(" ", "YouTube")
			$result | Should -BeTrue
		}

		It "Should return false for empty window title with no process name" {
			$result = Test-WindowTitleMatch -WindowTitle "" -Patterns @("*Something*")
			$result | Should -BeFalse
		}

		It "Should return false when no patterns match at all" {
			$result = Test-WindowTitleMatch -WindowTitle "test" -Patterns @("nope", "nada")
			$result | Should -BeFalse
		}
	}
}
