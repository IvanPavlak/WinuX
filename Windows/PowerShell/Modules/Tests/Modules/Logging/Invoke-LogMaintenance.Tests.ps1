#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Logging\Logging.psd1"
	Import-Module $ModulePath -Force

	$script:PrevConfig = $global:Configuration
}

AfterAll {
	$global:Configuration = $script:PrevConfig
	Remove-Variable -Name LoggingState -Scope Global -ErrorAction SilentlyContinue
	Remove-Module Logging -Force -ErrorAction SilentlyContinue
}

Describe "Invoke-LogMaintenance" {
	BeforeEach {
		$script:LogsDir = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
		$script:ResultsDir = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
		New-Item -ItemType Directory -Path $script:LogsDir -Force | Out-Null
		New-Item -ItemType Directory -Path $script:ResultsDir -Force | Out-Null

		$global:Configuration = @{
			Logging = @{
				FileLogging = @{
					Enabled   = $true
					Retention = @{ MaxAgeDays = 0; MaxSessionFiles = 2; MaxTotalSizeMB = 0; MaxErrorFileSizeMB = 0 }
				}
				Maintenance = @{ Enabled = $true; IntervalHours = 24 }
			}
		}

		$global:LoggingState = @{
			Level       = 'Normal'
			Colors      = @{}
			FileLogging = $true
			LogsDir     = $script:LogsDir
			PinnedDir   = (Join-Path $script:LogsDir 'Pinned')
			SessionFile = (Join-Path $script:LogsDir 'Session_current.log')
			ErrorFile   = (Join-Path $script:LogsDir 'Errors.log')
			Config      = $global:Configuration.Logging
		}

		$script:StampFile = Join-Path $script:LogsDir '.last-maintenance'
	}

	Context "throttling and configuration" {
		BeforeEach {
			Mock -ModuleName Logging Clear-OldLogs { }
		}

		It "skips the sweep when the stamp is younger than the interval" {
			Set-Content -Path $script:StampFile -Value 'stamp'
			Invoke-LogMaintenance -ResultsDirectory $script:ResultsDir
			Should -Invoke -ModuleName Logging Clear-OldLogs -Times 0 -Exactly
		}

		It "runs the sweep when the stamp is older than the interval" {
			Set-Content -Path $script:StampFile -Value 'stamp'
			(Get-Item -Path $script:StampFile -Force).LastWriteTime = (Get-Date).AddHours(-25)
			Invoke-LogMaintenance -ResultsDirectory $script:ResultsDir
			Should -Invoke -ModuleName Logging Clear-OldLogs -Times 1 -Exactly
		}

		It "honors a custom IntervalHours from configuration" {
			$global:Configuration.Logging.Maintenance.IntervalHours = 1
			Set-Content -Path $script:StampFile -Value 'stamp'
			(Get-Item -Path $script:StampFile -Force).LastWriteTime = (Get-Date).AddHours(-2)
			Invoke-LogMaintenance -ResultsDirectory $script:ResultsDir
			Should -Invoke -ModuleName Logging Clear-OldLogs -Times 1 -Exactly
		}

		It "-Force bypasses a fresh stamp" {
			Set-Content -Path $script:StampFile -Value 'stamp'
			Invoke-LogMaintenance -Force -ResultsDirectory $script:ResultsDir
			Should -Invoke -ModuleName Logging Clear-OldLogs -Times 1 -Exactly
		}

		It "does nothing when Maintenance.Enabled is false" {
			$global:Configuration.Logging.Maintenance.Enabled = $false
			Invoke-LogMaintenance -ResultsDirectory $script:ResultsDir
			Should -Invoke -ModuleName Logging Clear-OldLogs -Times 0 -Exactly
		}

		It "-Force overrides Maintenance.Enabled = false" {
			$global:Configuration.Logging.Maintenance.Enabled = $false
			Invoke-LogMaintenance -Force -ResultsDirectory $script:ResultsDir
			Should -Invoke -ModuleName Logging Clear-OldLogs -Times 1 -Exactly
		}

		It "defaults to enabled when the Maintenance block is absent" {
			$global:Configuration.Logging.Remove('Maintenance')
			Invoke-LogMaintenance -ResultsDirectory $script:ResultsDir
			Should -Invoke -ModuleName Logging Clear-OldLogs -Times 1 -Exactly
		}

		It "writes the stamp file when it runs" {
			Invoke-LogMaintenance -ResultsDirectory $script:ResultsDir
			Test-Path $script:StampFile | Should -BeTrue
		}
	}

	Context "session-log retention" {
		It "prunes session logs through Clear-OldLogs using configured retention" {
			1..5 | ForEach-Object {
				$f = Join-Path $script:LogsDir ("Session_2026-01-{0:D2}_00-00-00_{1}.log" -f $_, $_)
				Set-Content -Path $f -Value 'x'
				(Get-Item $f).LastWriteTime = (Get-Date).AddHours( - $_)
			}
			Invoke-LogMaintenance -Force -ResultsDirectory $script:ResultsDir
			(Get-ChildItem $script:LogsDir -Filter 'Session_*.log' -File).Count | Should -Be 2
		}
	}

	Context "test-results pruning" {
		BeforeEach {
			Mock -ModuleName Logging Clear-OldLogs { }

			# Helper: create a file with a given age in days.
			$script:NewAgedFile = {
				param([string]$Name, [double]$AgeDays)
				$path = Join-Path $script:ResultsDir $Name
				Set-Content -Path $path -Value 'x'
				(Get-Item $path).LastWriteTime = (Get-Date).AddDays( - $AgeDays)
				$path
			}
		}

		It "keeps only the ten newest day-old run logs" {
			1..12 | ForEach-Object { & $script:NewAgedFile ("TestRun_2026-01-{0:D2}_00-00-00_{0}.log" -f $_) ($_ + 1) }
			Invoke-LogMaintenance -Force -ResultsDirectory $script:ResultsDir
			(Get-ChildItem $script:ResultsDir -Filter 'TestRun_*.log' -File).Count | Should -Be 10
		}

		It "never removes run logs younger than a day, even beyond the retained count" {
			1..12 | ForEach-Object { & $script:NewAgedFile ("TestRun_2026-01-{0:D2}_00-00-00_{0}.log" -f $_) 0.01 }
			Invoke-LogMaintenance -Force -ResultsDirectory $script:ResultsDir
			(Get-ChildItem $script:ResultsDir -Filter 'TestRun_*.log' -File).Count | Should -Be 12
		}

		It "removes day-old orphaned worker XMLs" {
			& $script:NewAgedFile 'pester-results-2026-01-01_00-00-00_111-worker0.xml' 2
			Invoke-LogMaintenance -Force -ResultsDirectory $script:ResultsDir
			(Get-ChildItem $script:ResultsDir -Filter 'pester-results-*.xml' -File).Count | Should -Be 0
		}

		It "keeps orphaned XMLs younger than a day (a run may still be in flight)" {
			& $script:NewAgedFile 'pester-results-2026-01-01_00-00-00_111-worker0.xml' 0.01
			Invoke-LogMaintenance -Force -ResultsDirectory $script:ResultsDir
			(Get-ChildItem $script:ResultsDir -Filter 'pester-results-*.xml' -File).Count | Should -Be 1
		}

		It "keeps XMLs whose run log still exists, regardless of age" {
			& $script:NewAgedFile 'TestRun_2026-01-01_00-00-00_111.log' 5
			& $script:NewAgedFile 'pester-results-2026-01-01_00-00-00_111-worker0.xml' 5
			Invoke-LogMaintenance -Force -ResultsDirectory $script:ResultsDir
			(Get-ChildItem $script:ResultsDir -Filter 'pester-results-*.xml' -File).Count | Should -Be 1
		}

		It "sweeps abandoned Work directories older than a day and keeps young ones" {
			$workRoot = Join-Path $script:ResultsDir 'Work'
			$old = Join-Path $workRoot 'run-old'
			$young = Join-Path $workRoot 'run-young'
			New-Item -ItemType Directory -Path $old, $young -Force | Out-Null
			(Get-Item $old).LastWriteTime = (Get-Date).AddDays(-2)
			Invoke-LogMaintenance -Force -ResultsDirectory $script:ResultsDir
			Test-Path $old | Should -BeFalse
			Test-Path $young | Should -BeTrue
		}

		It "never touches timings.json" {
			$timings = Join-Path $script:ResultsDir 'timings.json'
			Set-Content -Path $timings -Value '{}'
			(Get-Item $timings).LastWriteTime = (Get-Date).AddDays(-30)
			Invoke-LogMaintenance -Force -ResultsDirectory $script:ResultsDir
			Test-Path $timings | Should -BeTrue
		}

		It "returns quietly when the results directory does not exist" {
			{ Invoke-LogMaintenance -Force -ResultsDirectory (Join-Path $TestDrive 'missing') } | Should -Not -Throw
		}
	}
}
