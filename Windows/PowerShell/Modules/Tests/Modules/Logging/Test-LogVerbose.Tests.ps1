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

Describe "Test-LogVerbose" {
	It "returns false at Normal level" {
		Set-LogLevel Normal
		Test-LogVerbose | Should -BeFalse
	}

	It "returns true at Verbose level" {
		Set-LogLevel Verbose
		Test-LogVerbose | Should -BeTrue
		Set-LogLevel Normal
	}

	It "returns true when the GLOBAL VerbosePreference is Continue" {
		# Must be global: a module function reads $VerbosePreference from its own/global scope,
		# not from an arbitrary caller's local scope (the same reason Set-LogLevel is the primary control).
		Set-LogLevel Normal
		$global:VerbosePreference = 'Continue'
		try { Test-LogVerbose | Should -BeTrue }
		finally { $global:VerbosePreference = 'SilentlyContinue' }
	}

	It "returns false again after verbose is cleared" {
		Set-LogLevel Normal
		Test-LogVerbose | Should -BeFalse
	}
}
