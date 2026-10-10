#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	. (Join-Path $ModuleRoot "Tests\Read-WorkerHistory.ps1")
	. (Join-Path $ModuleRoot "Tests\Write-WorkerHistory.ps1")
	. (Join-Path $ModuleRoot "Tests\Test-WorkerSampleRecordable.ps1")
}

Describe "Read-WorkerHistory and Write-WorkerHistory" {
	BeforeEach {
		$script:HistoryFile = Join-Path $TestDrive ("workers_{0}.json" -f [guid]::NewGuid().ToString('N'))
	}

	It "reads a missing file as no history" {
		$history = Read-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|450'
		@($history.Runs).Count | Should -Be 0
		$history.Recorded | Should -Be 0
	}

	It "reads a corrupt file as no history instead of failing the run" {
		Set-Content -LiteralPath $script:HistoryFile -Value '{ not json'
		$history = Read-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|450'
		@($history.Runs).Count | Should -Be 0
	}

	It "returns what was written for the same fingerprint, counting every recorded run" {
		Write-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|450' -Sample @{ workers = 12; wallSec = 50.5 } | Should -BeTrue
		Write-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|450' -Sample @{ workers = 15; wallSec = 48.0 } | Should -BeTrue

		$history = Read-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|450'
		@($history.Runs).Count | Should -Be 2
		$history.Recorded | Should -Be 2
		@($history.Runs)[1].workers | Should -Be 15
	}

	It "restarts learning when the fingerprint changes" {
		Write-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|450' -Sample @{ workers = 12; wallSec = 50 } | Out-Null
		Write-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|450' -Sample @{ workers = 15; wallSec = 48 } | Out-Null

		@((Read-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|500').Runs).Count | Should -Be 0

		Write-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|500' -Sample @{ workers = 12; wallSec = 55 } | Out-Null
		$history = Read-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|500'
		@($history.Runs).Count | Should -Be 1
		$history.Recorded | Should -Be 1
	}

	It "matches a scoped run on the processor count alone" {
		Write-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|450' -Sample @{ workers = 12; wallSec = 50 } | Out-Null
		@((Read-WorkerHistory -Path $script:HistoryFile -ProcessorCount 16).Runs).Count | Should -Be 1
		@((Read-WorkerHistory -Path $script:HistoryFile -ProcessorCount 8).Runs).Count | Should -Be 0
	}

	It "keeps only the newest runs but keeps counting" {
		for ($i = 1; $i -le 7; $i++) {
			Write-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|450' -Sample @{ workers = 12; wallSec = $i } -Keep 5 | Out-Null
		}
		$history = Read-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|450'
		@($history.Runs).Count | Should -Be 5
		@($history.Runs)[0].wallSec | Should -Be 3
		$history.Recorded | Should -Be 7
	}

	It "keeps 60 runs by default" {
		for ($i = 1; $i -le 62; $i++) {
			Write-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|450' -Sample @{ workers = 12; wallSec = $i } | Out-Null
		}
		@((Read-WorkerHistory -Path $script:HistoryFile -Fingerprint '16|450').Runs).Count | Should -Be 60
	}

	It "reports failure instead of throwing when the file cannot be written" {
		# A file where the history's folder should be: nothing can be written beneath it.
		$blocked = Join-Path $TestDrive 'blocked'
		Set-Content -LiteralPath $blocked -Value 'not a folder'
		Write-WorkerHistory -Path (Join-Path $blocked 'workers.json') -Fingerprint '16|450' -Sample @{ workers = 12; wallSec = 1 } | Should -BeFalse
	}
}

Describe "Test-WorkerSampleRecordable" {
	It "records a full, green, quiet run" {
		(Test-WorkerSampleRecordable -FailedCount 0 -ForeignLoadPercent 2.5).Recordable | Should -BeTrue
	}

	It "records a run whose machine load is unknown" {
		(Test-WorkerSampleRecordable -FailedCount 0 -ForeignLoadPercent -1).Recordable | Should -BeTrue
	}

	It "does not record <Name>" -ForEach @(
		@{ Name = 'a CI run'; Arguments = @{ CI = $true } }
		@{ Name = 'an explicit -Workers run'; Arguments = @{ ExplicitWorkers = $true } }
		@{ Name = 'a scoped run'; Arguments = @{ Scoped = $true } }
		@{ Name = 'a run with failing tests'; Arguments = @{ FailedCount = 1 } }
		@{ Name = 'a run that did not complete cleanly'; Arguments = @{ InfrastructureError = $true } }
		@{ Name = 'a run on a busy machine'; Arguments = @{ ForeignLoadPercent = 15.1 } }
	) {
		(Test-WorkerSampleRecordable @Arguments).Recordable | Should -BeFalse
	}

	It "honours a different noise threshold" {
		(Test-WorkerSampleRecordable -ForeignLoadPercent 8 -MaxForeignLoadPercent 5).Recordable | Should -BeFalse
		(Test-WorkerSampleRecordable -ForeignLoadPercent 8 -MaxForeignLoadPercent 10).Recordable | Should -BeTrue
	}
}
