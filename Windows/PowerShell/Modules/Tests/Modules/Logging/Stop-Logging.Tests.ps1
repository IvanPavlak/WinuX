#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Logging\Logging.psd1"
	Import-Module $ModulePath -Force
}

AfterAll {
	Remove-Variable -Name LoggingState -Scope Global -ErrorAction SilentlyContinue
	Remove-Module Logging -Force -ErrorAction SilentlyContinue
}

Describe "Stop-Logging" {
	BeforeEach {
		$global:startTime = (Get-Date).AddSeconds(-90)
		$global:logPath = "C:\Users\You\Desktop\BootstrapLog_test.log"
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
		Mock -ModuleName Logging Stop-Transcript { }
		Mock -ModuleName Logging Write-Host { }
		Mock -ModuleName Logging Clear-OldLogs { }
	}

	It "stops the transcript" {
		Stop-Logging
		Should -Invoke -ModuleName Logging Stop-Transcript -Times 1 -Exactly
	}

	It "enforces retention on stop" {
		Stop-Logging
		Should -Invoke -ModuleName Logging Clear-OldLogs -Times 1 -Exactly
	}
}
