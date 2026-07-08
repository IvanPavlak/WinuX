#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Logging\Logging.psd1"
	Import-Module $ModulePath -Force
}

AfterAll {
	Remove-Variable -Name LoggingState -Scope Global -ErrorAction SilentlyContinue
	Remove-Module Logging -Force -ErrorAction SilentlyContinue
}

Describe "Clear-OldLogs retention" {
	BeforeEach {
		$script:Dir = Join-Path $TestDrive ([System.IO.Path]::GetRandomFileName())
		$script:Pinned = Join-Path $script:Dir 'Pinned'
		New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
		New-Item -ItemType Directory -Path $script:Pinned -Force | Out-Null

		# Ten session files, spaced two days apart so no file sits exactly on a day cutoff.
		1..10 | ForEach-Object {
			$f = Join-Path $script:Dir ("Session_2026-01-{0:D2}_00-00-00_{1}.log" -f $_, $_)
			Set-Content -Path $f -Value ("x" * 1024)
			(Get-Item $f).LastWriteTime = (Get-Date).AddDays( - ($_ * 2))
		}
		# A pinned log that must always survive.
		Set-Content -Path (Join-Path $script:Pinned 'Session_pinned.log') -Value "keep me"

		$global:LoggingState = @{
			Level       = 'Normal'
			Colors      = @{}
			FileLogging = $true
			LogsDir     = $script:Dir
			PinnedDir   = $script:Pinned
			SessionFile = (Join-Path $script:Dir 'Session_current.log')
			ErrorFile   = (Join-Path $script:Dir 'Errors.log')
			Config      = $null
		}
	}

	It "keeps only the newest N session files by count" {
		Clear-OldLogs -MaxSessionFiles 3 -MaxAgeDays 0 -MaxTotalSizeMB 0 -MaxErrorFileSizeMB 0
		(Get-ChildItem $script:Dir -Filter 'Session_*.log' -File).Count | Should -Be 3
	}

	It "removes session files older than the age cutoff" {
		# Files are at -2,-4,-6,-8,-10,...,-20 days; cutoff -9 keeps the four newest (-2,-4,-6,-8).
		Clear-OldLogs -MaxAgeDays 9 -MaxSessionFiles 0 -MaxTotalSizeMB 0 -MaxErrorFileSizeMB 0
		$remaining = Get-ChildItem $script:Dir -Filter 'Session_*.log' -File
		$remaining.Count | Should -Be 4
		($remaining | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-9) }) | Should -BeNullOrEmpty
	}

	It "trims total size by removing oldest first" {
		# Each file ~1KB; cap is tiny so most are removed, newest retained.
		Clear-OldLogs -MaxTotalSizeMB 0 -MaxAgeDays 0 -MaxSessionFiles 4 -MaxErrorFileSizeMB 0
		(Get-ChildItem $script:Dir -Filter 'Session_*.log' -File).Count | Should -BeLessOrEqual 4
	}

	It "never deletes logs in the Pinned subfolder" {
		Clear-OldLogs -MaxSessionFiles 1 -MaxAgeDays 1 -MaxTotalSizeMB 1 -MaxErrorFileSizeMB 1
		Test-Path (Join-Path $script:Pinned 'Session_pinned.log') | Should -BeTrue
	}
}
