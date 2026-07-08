#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Logging\Logging.psd1"
	Import-Module $ModulePath -Force
	Initialize-LoggingState -Force | Out-Null
}

AfterAll {
	Remove-Variable -Name LoggingState -Scope Global -ErrorAction SilentlyContinue
	Remove-Module Logging -Force -ErrorAction SilentlyContinue
}

Describe "Set-LogLevel" {
	Context "Persistent form" {
		It "sets the global level" {
			Set-LogLevel Verbose
			$global:LoggingState.Level | Should -Be 'Verbose'
			Set-LogLevel Normal
			$global:LoggingState.Level | Should -Be 'Normal'
		}

		It "rejects an invalid level" {
			{ Set-LogLevel Loud } | Should -Throw
		}
	}

	Context "Scoped form" {
		It "applies the level only while the command runs, then restores" {
			Set-LogLevel Normal
			# The scriptblock's output flows back through Set-LogLevel, so capture the level it saw.
			$observed = Set-LogLevel Verbose { $global:LoggingState.Level }
			$observed | Should -Be 'Verbose'
			$global:LoggingState.Level | Should -Be 'Normal'
		}

		It "restores the previous level even if the command throws" {
			Set-LogLevel Normal
			{ Set-LogLevel Verbose { throw "fail" } } | Should -Throw
			$global:LoggingState.Level | Should -Be 'Normal'
		}

		It "restores to whatever the previous level was (not hardcoded Normal)" {
			Set-LogLevel Quiet
			Set-LogLevel Verbose { }
			$global:LoggingState.Level | Should -Be 'Quiet'
			Set-LogLevel Normal
		}
	}
}
