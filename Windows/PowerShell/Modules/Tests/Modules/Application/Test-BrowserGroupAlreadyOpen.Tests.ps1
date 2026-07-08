#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$configurationPath = Join-Path (Get-RepositoryPath).PowerShell "Configuration.psd1"
	$global:Configuration = Import-PowerShellDataFile -Path $configurationPath

	# Import the Application module function for testing
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Test-BrowserGroupAlreadyOpen.ps1"

	# Helper function to create mock browser window objects
	function New-MockBrowserWindow {
		param([string]$Title)
		return [PSCustomObject]@{ Title = $Title }
	}

	# Helper function to create arrays of mock windows
	function New-MockBrowserWindows {
		param([string[]]$Titles)
		return $Titles | ForEach-Object { New-MockBrowserWindow -Title $_ }
	}
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Test-BrowserGroupAlreadyOpen" {
	Context "Basic Keyword Extraction" {
		BeforeEach {
			# Mock Get-WindowHandle to return empty (no windows open)
			Mock Get-WindowHandle { @() }
		}

		It "Should extract domain keyword from simple URL" {
			# Even though no windows match, the function should correctly extract keywords
			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.youtube.com/") `
				-Browser "Firefox" -GroupDisplayName "YouTube"

			$result | Should -Be $false
		}

		It "Should extract subdomain keyword from subdomain URLs" {
			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://gemini.google.com/") `
				-Browser "Firefox" -GroupDisplayName "Gemini"

			$result | Should -Be $false
		}

		It "Should extract path keywords from URL paths" {
			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://example.com/documentation/api-reference") `
				-Browser "Firefox" -GroupDisplayName "API Docs"

			$result | Should -Be $false
		}
	}

	Context "Basic Matching - Single URL, Single Window" {
		It "Should return true when window title contains domain keyword" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("YouTube - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.youtube.com/") `
				-Browser "Firefox" -GroupDisplayName "YouTube"

			$result | Should -Be $true
		}

		It "Should return false when no window matches" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("GitHub - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.youtube.com/") `
				-Browser "Firefox" -GroupDisplayName "YouTube"

			$result | Should -Be $false
		}

		It "Should be case-insensitive when matching" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("YOUTUBE - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.youtube.com/") `
				-Browser "Firefox" -GroupDisplayName "YouTube"

			$result | Should -Be $true
		}
	}

	Context "Main Homepage Detection with Negative Matching" {
		It "Should NOT match 'Google Gemini' window when checking for google.com" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @(
					"YouTube - Mozilla Firefox",
					"Google Gemini - Mozilla Firefox",
					"GitHub - Mozilla Firefox"
				)
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.google.com/") `
				-Browser "Firefox" -GroupDisplayName "Google"

			$result | Should -Be $false
		}

		It "Should NOT match 'Google Drive' window when checking for google.com" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Google Drive - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.google.com/") `
				-Browser "Firefox" -GroupDisplayName "Google"

			$result | Should -Be $false
		}

		It "Should NOT match 'Google Maps' window when checking for google.com" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Google Maps - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.google.com/") `
				-Browser "Firefox" -GroupDisplayName "Google"

			$result | Should -Be $false
		}

		It "Should NOT match 'Gmail' window when checking for google.com" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Inbox - user@gmail.com - Gmail - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.google.com/") `
				-Browser "Firefox" -GroupDisplayName "Google"

			$result | Should -Be $false
		}

		It "Should match exact 'Google' title when checking for google.com" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @(
					"Google Gemini - Mozilla Firefox",
					"Google - Mozilla Firefox"
				)
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.google.com/") `
				-Browser "Firefox" -GroupDisplayName "Google"

			$result | Should -Be $true
		}

		It "Should NOT match Microsoft Outlook when checking for microsoft.com" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Outlook - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.microsoft.com/") `
				-Browser "Firefox" -GroupDisplayName "Microsoft"

			$result | Should -Be $false
		}

		It "Should NOT match Microsoft Teams when checking for microsoft.com" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Microsoft Teams - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.microsoft.com/") `
				-Browser "Firefox" -GroupDisplayName "Microsoft"

			$result | Should -Be $false
		}
	}

	Context "Subdomain URL Matching" {
		It "Should match 'gemini' window when checking for gemini.google.com" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @(
					"YouTube - Mozilla Firefox",
					"Google Gemini - Mozilla Firefox"
				)
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://gemini.google.com/") `
				-Browser "Firefox" -GroupDisplayName "Gemini"

			$result | Should -Be $true
		}

		It "Should match AI Studio when checking for aistudio.google.com" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Google AI Studio - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://aistudio.google.com/") `
				-Browser "Firefox" -GroupDisplayName "AI Studio"

			$result | Should -Be $true
		}

		It "Should match Claude when checking for claude.ai" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Claude - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://claude.ai/") `
				-Browser "Firefox" -GroupDisplayName "Claude"

			$result | Should -Be $true
		}

		It "Should match ChatGPT when checking for chat.openai.com" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("ChatGPT - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://chat.openai.com/") `
				-Browser "Firefox" -GroupDisplayName "ChatGPT"

			$result | Should -Be $true
		}

		It "Should match Perplexity when checking for perplexity.ai" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Perplexity - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://perplexity.ai/") `
				-Browser "Firefox" -GroupDisplayName "Perplexity"

			$result | Should -Be $true
		}

		It "Should treat 'app' subdomain as generic and match domain as Primary" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("general (Channel) - myworkspace - Slack - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://app.slack.com/client/T000000000/C000000000") `
				-Browser "Firefox" -GroupDisplayName "SlackWeb"

			$result | Should -Be $true
		}

		It "Should match Gmail title when checking for mail.google.com" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Gmail - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://mail.google.com/mail/u/0/#inbox") `
				-Browser "Firefox" -GroupDisplayName "Email"

			$result | Should -Be $true
		}

		It "Should match Inbox title from mail.google.com fragment" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Inbox - user@gmail.com - Gmail - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://mail.google.com/mail/u/0/#inbox") `
				-Browser "Firefox" -GroupDisplayName "Email"

			$result | Should -Be $true
		}
	}

	Context "Multiple URLs in Group" {
		It "Should match if any URL from group matches a window" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("GitHub - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @(
				"https://github.com/",
				"https://gitlab.com/",
				"https://bitbucket.org/"
			) -Browser "Firefox" -GroupDisplayName "Git Hosting"

			$result | Should -Be $true
		}

		It "Should return false if no URLs from group match" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Stack Overflow - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @(
				"https://github.com/",
				"https://gitlab.com/"
			) -Browser "Firefox" -GroupDisplayName "Git Hosting"

			$result | Should -Be $false
		}
	}

	Context "Multiple Browser Windows" {
		It "Should scan all windows and find match anywhere" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @(
					"YouTube - Mozilla Firefox",
					"Wikipedia - Mozilla Firefox",
					"Stack Overflow - Mozilla Firefox",
					"GitHub Copilot - Mozilla Firefox"
				)
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://github.com/") `
				-Browser "Firefox" -GroupDisplayName "GitHub"

			$result | Should -Be $true
		}

		It "Should return false when many windows exist but none match" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @(
					"YouTube - Mozilla Firefox",
					"Wikipedia - Mozilla Firefox",
					"Stack Overflow - Mozilla Firefox"
				)
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://reddit.com/") `
				-Browser "Firefox" -GroupDisplayName "Reddit"

			$result | Should -Be $false
		}
	}

	Context "Browser Process Name Mapping" {
		It "Should use 'firefox' process name for Firefox browser" {
			Mock Get-WindowHandle { @() } -ParameterFilter { $ProcessName -eq "firefox" }
			Mock Get-WindowHandle { throw "Wrong process name" } -ParameterFilter { $ProcessName -ne "firefox" }

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://example.com/") `
				-Browser "Firefox" -GroupDisplayName "Example"

			$result | Should -Be $false
			Should -Invoke Get-WindowHandle -ParameterFilter { $ProcessName -eq "firefox" }
		}

		It "Should use 'chrome' process name for Chrome browser" {
			Mock Get-WindowHandle { @() } -ParameterFilter { $ProcessName -eq "chrome" }

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://example.com/") `
				-Browser "Chrome" -GroupDisplayName "Example"

			$result | Should -Be $false
			Should -Invoke Get-WindowHandle -ParameterFilter { $ProcessName -eq "chrome" }
		}

		It "Should use 'msedge' process name for Edge browser" {
			Mock Get-WindowHandle { @() } -ParameterFilter { $ProcessName -eq "msedge" }

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://example.com/") `
				-Browser "Edge" -GroupDisplayName "Example"

			$result | Should -Be $false
			Should -Invoke Get-WindowHandle -ParameterFilter { $ProcessName -eq "msedge" }
		}

		It "Should use 'firefox' process name for Tor browser" {
			Mock Get-WindowHandle { @() } -ParameterFilter { $ProcessName -eq "firefox" }

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://example.com/") `
				-Browser "Tor" -GroupDisplayName "Example"

			$result | Should -Be $false
			Should -Invoke Get-WindowHandle -ParameterFilter { $ProcessName -eq "firefox" }
		}
	}

	Context "Empty and Null Handling" {
		It "Should return false when no browser windows exist" {
			Mock Get-WindowHandle { $null }

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://example.com/") `
				-Browser "Firefox" -GroupDisplayName "Example"

			$result | Should -Be $false
		}

		It "Should return false when Get-WindowHandle returns empty array" {
			Mock Get-WindowHandle { @() }

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://example.com/") `
				-Browser "Firefox" -GroupDisplayName "Example"

			$result | Should -Be $false
		}

		It "Should skip windows with empty titles" {
			Mock Get-WindowHandle {
				@(
					[PSCustomObject]@{ Title = "" },
					[PSCustomObject]@{ Title = $null },
					[PSCustomObject]@{ Title = "GitHub - Mozilla Firefox" }
				)
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://github.com/") `
				-Browser "Firefox" -GroupDisplayName "GitHub"

			$result | Should -Be $true
		}
	}

	Context "Localhost URL Handling" {
		It "Should detect localhost URLs and match port numbers" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("localhost:3000 - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("http://localhost:3000/") `
				-Browser "Firefox" -GroupDisplayName "Dev Server"

			$result | Should -Be $true
		}

		It "Should detect 'Problem loading page' for failed localhost URLs" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Problem loading page - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("http://localhost:8080/") `
				-Browser "Firefox" -GroupDisplayName "Dev Server"

			$result | Should -Be $true
		}

		It "Should NOT assume 'Problem loading page' is localhost if URLs are not localhost" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Problem loading page - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://example.com/") `
				-Browser "Firefox" -GroupDisplayName "Example"

			$result | Should -Be $false
		}
	}

	Context "URL Path Matching" {
		It "Should extract and match path components" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Documentation Guide - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://docs.example.com/documentation/guide") `
				-Browser "Firefox" -GroupDisplayName "Docs"

			$result | Should -Be $true
		}

		It "Should handle slugified path components (dashes to spaces)" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Minor Illusion Spell - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://dnd.example.com/spell/minor-illusion") `
				-Browser "Firefox" -GroupDisplayName "DnD Spell"

			$result | Should -Be $true
		}

		It "Should handle underscore-separated path components" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("API Reference - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://api.example.com/api_reference") `
				-Browser "Firefox" -GroupDisplayName "API"

			$result | Should -Be $true
		}

		It "Should extract keyword after colon in path (spell:minor-illusion pattern)" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Minor Illusion - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://example.com/spell:minor-illusion") `
				-Browser "Firefox" -GroupDisplayName "Spells"

			$result | Should -Be $true
		}
	}

	Context "Score-Based Matching" {
		It "Should prefer longer keyword matches (higher confidence)" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("StackOverflow Q&A - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://stackoverflow.com/questions/12345") `
				-Browser "Firefox" -GroupDisplayName "Stack Overflow"

			$result | Should -Be $true
		}

		It "Should match even with low score if keyword is found" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("test - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://test.com/") `
				-Browser "Firefox" -GroupDisplayName "Test"

			$result | Should -Be $true
		}
	}

	Context "Domain Fallback Matching" {
		It "Should match full domain in title as fallback" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("https://www.example.com - Page Title - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.example.com/") `
				-Browser "Firefox" -GroupDisplayName "Example"

			$result | Should -Be $true
		}
	}

	Context "Browser Title Format Variations" {
		It "Should match Chrome title format (with dash)" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("YouTube - Google Chrome")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.youtube.com/") `
				-Browser "Chrome" -GroupDisplayName "YouTube"

			$result | Should -Be $true
		}

		It "Should match Edge title format" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("YouTube - Microsoft Edge")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.youtube.com/") `
				-Browser "Edge" -GroupDisplayName "YouTube"

			$result | Should -Be $true
		}

		It "Should match Firefox title format (with em dash)" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("YouTube - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.youtube.com/") `
				-Browser "Firefox" -GroupDisplayName "YouTube"

			$result | Should -Be $true
		}
	}

	Context "Word Boundary Matching" {
		It "Should NOT match partial word within larger word" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Pygithub Documentation - Mozilla Firefox")
			}

			# "hub" should not match "Pygithub" due to word boundary check
			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://hub.example.com/") `
				-Browser "Firefox" -GroupDisplayName "Hub"

			$result | Should -Be $false
		}

		It "Should match word at start of title" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("GitHub - Repository - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://github.com/") `
				-Browser "Firefox" -GroupDisplayName "GitHub"

			$result | Should -Be $true
		}

		It "Should match word at end of title (before browser name)" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Welcome to GitHub - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://github.com/") `
				-Browser "Firefox" -GroupDisplayName "GitHub"

			$result | Should -Be $true
		}

		It "Should NOT match GitHub profile slug inside a Gmail address" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Inbox - user@gmail.com - Gmail - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://github.com/ExampleUser") `
				-Browser "Firefox" -GroupDisplayName "GitHub - Personal - PersonalProfile"

			$result | Should -Be $false
		}

		It "Should match a GitHub profile title for a single-segment profile URL" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("ExampleUser (Example User) · GitHub - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://github.com/ExampleUser") `
				-Browser "Firefox" -GroupDisplayName "GitHub - Personal - PersonalProfile"

			$result | Should -Be $true
		}
	}

	Context "Error Handling" {
		It "Should return false when Get-WindowHandle throws" {
			Mock Get-WindowHandle { throw "Access denied" }

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://example.com/") `
				-Browser "Firefox" -GroupDisplayName "Example"

			$result | Should -Be $false
		}

		It "Should handle malformed URLs gracefully" {
			Mock Get-WindowHandle { @() }

			$result = Test-BrowserGroupAlreadyOpen -Urls @("not-a-valid-url") `
				-Browser "Firefox" -GroupDisplayName "Invalid"

			$result | Should -Be $false
		}
	}

	Context "Real-World Scenarios" {
		It "Scenario: Developer with multiple Google services open should correctly identify Google Search" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @(
					"YouTube - Mozilla Firefox",
					"ExampleUser/WinuX: WinuX Repository - Mozilla Firefox",
					"Google Gemini - Mozilla Firefox",
					"Google Drive - My Drive - Mozilla Firefox",
					"Google - Mozilla Firefox"
				)
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.google.com/") `
				-Browser "Firefox" -GroupDisplayName "Google"

			$result | Should -Be $true
		}

		It "Scenario: Developer with multiple Google services but NO Google Search should not false-positive" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @(
					"YouTube - Mozilla Firefox",
					"ExampleUser/WinuX: WinuX Repository - Mozilla Firefox",
					"Google Gemini - Mozilla Firefox",
					"Google Drive - My Drive - Mozilla Firefox",
					"Gmail - Inbox - Mozilla Firefox"
				)
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://www.google.com/") `
				-Browser "Firefox" -GroupDisplayName "Google"

			$result | Should -Be $false
		}

		It "Scenario: Checking for Gemini when multiple AI tools are open" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @(
					"Claude - Mozilla Firefox",
					"ChatGPT - Mozilla Firefox",
					"Google Gemini - Mozilla Firefox",
					"Perplexity - Mozilla Firefox"
				)
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://gemini.google.com/") `
				-Browser "Firefox" -GroupDisplayName "Gemini"

			$result | Should -Be $true
		}

		It "Scenario: Checking for GitHub repo when many dev tabs open" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @(
					"Stack Overflow - Mozilla Firefox",
					"npm - package search - Mozilla Firefox",
					"microsoft/vscode: Visual Studio Code - Mozilla Firefox",
					"Rust Documentation - Mozilla Firefox"
				)
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://github.com/microsoft/vscode") `
				-Browser "Firefox" -GroupDisplayName "VS Code Repo"

			$result | Should -Be $true
		}

		It "Scenario: Multiple URL group with partial open state" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @(
					"Reddit - Mozilla Firefox"
					# Twitter and HackerNews NOT open
				)
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @(
				"https://reddit.com/",
				"https://twitter.com/",
				"https://news.ycombinator.com/"
			) -Browser "Firefox" -GroupDisplayName "Social Media"

			# Should return true because Reddit (one of the group URLs) is already open
			$result | Should -Be $true
		}

		It "Scenario: AI group should NOT false-positive on Google homepage window" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @(
					"Google - Mozilla Firefox",
					"Homepage - Mozilla Firefox",
					"YouTube - Mozilla Firefox"
				)
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @(
				"https://gemini.google.com/",
				"https://aistudio.google.com/prompts/new_chat",
				"https://www.perplexity.ai/",
				"https://chat.openai.com/",
				"https://claude.ai/new"
			) -Browser "Firefox" -GroupDisplayName "AI"

			# "google" keyword is Secondary (from parent domain) and "Google - Mozilla Firefox"
			# contains no Primary keywords from the AI group → should NOT match
			$result | Should -Be $false
		}

		It "Scenario: AI group should match when Gemini tab is open" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @(
					"Google - Mozilla Firefox",
					"Google Gemini - Mozilla Firefox",
					"YouTube - Mozilla Firefox"
				)
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @(
				"https://gemini.google.com/",
				"https://aistudio.google.com/prompts/new_chat",
				"https://www.perplexity.ai/",
				"https://chat.openai.com/",
				"https://claude.ai/new"
			) -Browser "Firefox" -GroupDisplayName "AI"

			$result | Should -Be $true
		}

		It "Scenario: AI group should match when Claude tab is open" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @(
					"Google - Mozilla Firefox",
					"Claude - Mozilla Firefox",
					"YouTube - Mozilla Firefox"
				)
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @(
				"https://gemini.google.com/",
				"https://aistudio.google.com/prompts/new_chat",
				"https://www.perplexity.ai/",
				"https://chat.openai.com/",
				"https://claude.ai/new"
			) -Browser "Firefox" -GroupDisplayName "AI"

			$result | Should -Be $true
		}
	}

	Context "Generic Word Filtering" {
		It "Should not use 'home' as a keyword (too generic)" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Home Page - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://example.com/home") `
				-Browser "Firefox" -GroupDisplayName "Example"

			# Should not match just because "home" appears - needs "example" keyword
			$result | Should -Be $false
		}

		It "Should not use 'index' as a keyword (too generic)" {
			Mock Get-WindowHandle {
				New-MockBrowserWindows @("Index - Mozilla Firefox")
			}

			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://example.com/index.html") `
				-Browser "Firefox" -GroupDisplayName "Example"

			$result | Should -Be $false
		}

		It "Should not match short path keywords embedded in longer words" {
			Mock Get-WindowHandle {
				# "api" is part of "capital" - should NOT match due to word boundary check
				New-MockBrowserWindows @("Capital One Banking - Mozilla Firefox")
			}

			# Even though there's a short keyword "api" in the URL, it shouldn't match
			# "Capital" because word boundaries require the keyword to be a distinct word
			$result = Test-BrowserGroupAlreadyOpen -Urls @("https://example.com/api/users") `
				-Browser "Firefox" -GroupDisplayName "API Endpoint"

			$result | Should -Be $false
		}
	}
}
