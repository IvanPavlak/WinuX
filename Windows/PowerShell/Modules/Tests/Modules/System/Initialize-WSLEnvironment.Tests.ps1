#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Initialize-WSLEnvironment.ps1"
}

Describe "Initialize-WSLEnvironment" {
	BeforeEach {
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
}
