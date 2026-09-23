#Requires -Modules Pester

BeforeAll {
	# Put back exactly the logging state this file found. Deleting it instead made the next
	# file's first Write-Log rebuild the state from whatever test configuration was current -
	# file logging on by default - so the rest of the worker paid a call-stack walk and a
	# session-log append per log line and wrote test output into the real Logs folder.
	$script:SavedLoggingState = $global:LoggingState
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Logging\Logging.psd1"
	Import-Module $ModulePath -Force
}

AfterAll {
	$global:LoggingState = $script:SavedLoggingState
	Remove-Module Logging -Force -ErrorAction SilentlyContinue
}

Describe "Start-Logging" {
	BeforeEach {
		$env:USERPROFILE = "C:\Users\You"
		# Pre-seed state with file logging off so the test does not write to disk.
		$global:LoggingState = @{
			Level       = 'Normal'
			Colors      = @{ Title = 'DarkCyan'; Step = 'White'; Success = 'Green'; Warning = 'Yellow'; Error = 'Red'; Debug = 'DarkCyan' }
			FileLogging = $false
			LogsDir     = $TestDrive
			PinnedDir   = (Join-Path $TestDrive 'Pinned')
			SessionFile = (Join-Path $TestDrive 'session.log')
			ErrorFile   = (Join-Path $TestDrive 'errors.log')
			Config      = $null
		}
		Mock -ModuleName Logging Start-Transcript { }
		Mock -ModuleName Logging Write-Host { }
	}

	It "starts the transcript and initializes the global logging variables" {
		Start-Logging

		$global:logPath | Should -Match "BootstrapLog_"
		$global:startTime | Should -Not -BeNullOrEmpty
		Should -Invoke -ModuleName Logging Start-Transcript -Times 1 -Exactly
	}

	It "targets the Desktop for the transcript (fresh-machine parity)" {
		Start-Logging
		$global:logPath | Should -BeLike "*\Desktop\BootstrapLog_*.log"
	}
}
