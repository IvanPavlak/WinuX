#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Initialize-WSLEnvironment.ps1"
}

Describe "Initialize-WSLEnvironment" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			DefaultWSLDistribution = "Ubuntu"
			Universal              = [PSCustomObject]@{
				OhMyPoshThemeFile = "C:\themes\WinuX.omp.json"
			}
		}

		Mock wsl {
			if ($args -join ' ' -match "command -v fastfetch") {
				"true"
			}
			elseif ($args -join ' ' -match "grep -q 'fastfetch'") {
				"exists"
			}
		}
		Mock Write-Host { }
	}

	It "skips fastfetch install when already installed and still completes setup" {
		{ Initialize-WSLEnvironment } | Should -Not -Throw

		Should -Invoke wsl -Times 6
	}

	It "targets the configured distribution on every wsl call" {
		{ Initialize-WSLEnvironment } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { ($args -join ' ') -notmatch '-d Ubuntu' } -Times 0
	}

	It "skips when no WSL distribution is configured" {
		$script:Configuration = [PSCustomObject]@{
			DefaultWSLDistribution = ""
			Universal              = [PSCustomObject]@{ OhMyPoshThemeFile = "" }
		}

		{ Initialize-WSLEnvironment } | Should -Not -Throw

		Should -Invoke wsl -Times 0
	}
}
