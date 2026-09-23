#Requires -Modules Pester

BeforeAll {
	# Put back exactly the logging state this file found. Deleting it instead made the next
	# file's first Write-Log rebuild the state from whatever test configuration was current -
	# file logging on by default - so the rest of the worker paid a call-stack walk and a
	# session-log append per log line and wrote test output into the real Logs folder.
	$script:SavedLoggingState = $global:LoggingState
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Logging\Logging.psd1"
	Import-Module $ModulePath -Force
	Initialize-LoggingState -Force | Out-Null
}

AfterAll {
	$global:LoggingState = $script:SavedLoggingState
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
