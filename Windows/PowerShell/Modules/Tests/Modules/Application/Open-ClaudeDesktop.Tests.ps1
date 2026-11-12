#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-ClaudeDesktop.ps1"
}

Describe "Open-ClaudeDesktop" {
	BeforeEach {
		Mock Start-Application { }
	}

	It "delegates to Start-Application with the Claude Desktop launcher, without arguments" {
		Open-ClaudeDesktop

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'Claude' -and
			$ProcessName -eq 'claude' -and
			$StartMethod -eq 'DirectPath' -and
			$ExecutablePath -eq "$env:LOCALAPPDATA\AnthropicClaude\claude.exe" -and
			-not $Arguments
		}
	}

	It "scopes the running check to the Claude Desktop install directory so the Claude Code CLI is ignored" {
		Open-ClaudeDesktop

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$ProcessPathFilter -eq "$env:LOCALAPPDATA\AnthropicClaude\*"
		}
	}

	It "requires a visible main window so the background processes of a closed app are ignored" {
		Open-ClaudeDesktop

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$RequireMainWindow -eq $true
		}
	}
}
