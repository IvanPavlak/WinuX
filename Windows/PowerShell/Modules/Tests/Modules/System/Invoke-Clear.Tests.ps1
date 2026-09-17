#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Invoke-Clear.ps1"
	. "$FunctionsPath\Resolve-TerminalGreetingSettings.ps1"

	if (-not (Get-Command Write-LogDebug -ErrorAction SilentlyContinue)) {
		function Write-LogDebug { param([string]$Message, [string]$Style) }
	}
	if (-not (Get-Command Write-LogWarning -ErrorAction SilentlyContinue)) {
		function Write-LogWarning { param([string]$Message) }
	}
}

Describe "Invoke-Clear" {
	BeforeEach {
		Mock Clear-Host { }

		$script:SavedConfiguration = $global:Configuration
		$global:Configuration = @{}
	}

	AfterEach { $global:Configuration = $script:SavedConfiguration }

	It "calls Clear-Host once" {
		Invoke-Clear

		Should -Invoke Clear-Host -Times 1 -Exactly
	}

	It "resolves its own settings when none are passed, so it is usable on its own" {
		$global:Configuration = @{ TerminalGreeting = @{ Clear = @{ Enabled = $false } } }

		Invoke-Clear

		Should -Invoke Clear-Host -Times 0 -Exactly
	}

	It "does nothing when the passed settings have the clear step off" {
		$settings = Resolve-TerminalGreetingSettings -Settings @{ Clear = @{ Enabled = $false } }

		Invoke-Clear -Settings $settings

		Should -Invoke Clear-Host -Times 0 -Exactly
	}

	It "clears when the passed settings have the clear step on" {
		$settings = Resolve-TerminalGreetingSettings -Settings @{ Clear = @{ Enabled = $true } }

		Invoke-Clear -Settings $settings

		Should -Invoke Clear-Host -Times 1 -Exactly
	}
}
