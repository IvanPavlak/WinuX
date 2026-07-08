#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Logging\Logging.psd1"
	Import-Module $ModulePath -Force
}

AfterAll {
	Remove-Variable -Name LoggingState -Scope Global -ErrorAction SilentlyContinue
	Remove-Module Logging -Force -ErrorAction SilentlyContinue
}

Describe "Protect-Log" {
	BeforeEach {
		$script:Dir = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
		$script:Pinned = Join-Path $script:Dir 'Pinned'
		New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
		$script:Session = Join-Path $script:Dir 'Session_current.log'
		Set-Content -Path $script:Session -Value "session content"

		$global:LoggingState = @{
			Level       = 'Normal'
			Colors      = @{ Title = 'DarkCyan'; Step = 'White'; Success = 'Green'; Warning = 'Yellow'; Error = 'Red'; Debug = 'DarkCyan' }
			FileLogging = $true
			LogsDir     = $script:Dir
			PinnedDir   = $script:Pinned
			SessionFile = $script:Session
			ErrorFile   = (Join-Path $script:Dir 'Errors.log')
			Config      = $null
		}
	}

	It "copies the current session log into Pinned and leaves the original in place" {
		Protect-Log
		Test-Path (Join-Path $script:Pinned 'Session_current.log') | Should -BeTrue
		Test-Path $script:Session | Should -BeTrue
	}

	It "creates the Pinned folder if it does not exist" {
		Test-Path $script:Pinned | Should -BeFalse
		Protect-Log
		Test-Path $script:Pinned | Should -BeTrue
	}

	It "pins an explicitly provided path" {
		$other = Join-Path $script:Dir 'Session_other.log'
		Set-Content -Path $other -Value "other"
		Protect-Log -Path $other
		Test-Path (Join-Path $script:Pinned 'Session_other.log') | Should -BeTrue
	}

	It "warns and does nothing when the target file is missing" {
		$global:LoggingState.SessionFile = Join-Path $script:Dir 'does-not-exist.log'
		Mock -ModuleName Logging Write-Host {}
		Protect-Log
		(Get-ChildItem $script:Pinned -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
	}
}
