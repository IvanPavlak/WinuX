#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Clear-OldBackups.ps1"

	$script:SavedConfiguration = $global:Configuration

	# Builds <root>\<category>\<key>\<stamp>\payload.txt with a chosen size and age.
	function New-TestBackup {
		param($Root, $Category, $Key, $Stamp, [int]$SizeBytes = 10, [int]$AgeDays = 0)
		$dir = Join-Path $Root "$Category\$Key\$Stamp"
		New-Item -ItemType Directory -Path $dir -Force | Out-Null
		Set-Content -Path (Join-Path $dir "payload.txt") -Value ("x" * $SizeBytes) -NoNewline
		if ($AgeDays -gt 0) {
			(Get-Item -Path $dir).LastWriteTime = (Get-Date).AddDays(-$AgeDays)
		}
		return $dir
	}
}

AfterAll {
	$global:Configuration = $script:SavedConfiguration
}

Describe "Clear-OldBackups" {
	BeforeEach {
		$global:Configuration = @{}
		$script:Root = Join-Path $TestDrive "Sink"
		New-Item -ItemType Directory -Path $script:Root -Force | Out-Null
	}

	AfterEach {
		Remove-Item -Path $script:Root -Recurse -Force -ErrorAction SilentlyContinue
	}

	Context "Per-key count limit" {
		It "Keeps only the newest N backups of every key" {
			foreach ($stamp in "2020-01-01_00-00-01", "2020-01-01_00-00-02", "2020-01-01_00-00-03") {
				New-TestBackup -Root $script:Root -Category "Config" -Key "K" -Stamp $stamp | Out-Null
			}

			Clear-OldBackups -BackupRoot $script:Root -MaxBackupsPerKey 2 -MaxAgeDays 0 -MaxTotalSizeMB 0

			$remaining = @(Get-ChildItem -Path (Join-Path $script:Root "Config\K") -Directory | Sort-Object Name)
			$remaining.Name | Should -Be @("2020-01-01_00-00-02", "2020-01-01_00-00-03")
		}

		It "Does not prune when the limit is 0" {
			foreach ($stamp in "2020-01-01_00-00-01", "2020-01-01_00-00-02", "2020-01-01_00-00-03") {
				New-TestBackup -Root $script:Root -Category "Config" -Key "K" -Stamp $stamp | Out-Null
			}

			Clear-OldBackups -BackupRoot $script:Root -MaxBackupsPerKey 0 -MaxAgeDays 0 -MaxTotalSizeMB 0

			@(Get-ChildItem -Path (Join-Path $script:Root "Config\K") -Directory).Count | Should -Be 3
		}
	}

	Context "Age limit" {
		It "Removes backups older than the cutoff" {
			New-TestBackup -Root $script:Root -Category "Config" -Key "K" -Stamp "2020-01-01_00-00-01" -AgeDays 30 | Out-Null
			New-TestBackup -Root $script:Root -Category "Config" -Key "K" -Stamp "2020-01-01_00-00-02" -AgeDays 30 | Out-Null
			New-TestBackup -Root $script:Root -Category "Config" -Key "K" -Stamp "2020-01-01_00-00-03" | Out-Null

			Clear-OldBackups -BackupRoot $script:Root -MaxAgeDays 7 -MaxBackupsPerKey 0 -MaxTotalSizeMB 0

			$remaining = @(Get-ChildItem -Path (Join-Path $script:Root "Config\K") -Directory | Sort-Object Name)
			$remaining.Name | Should -Be @("2020-01-01_00-00-03")
		}

		It "Never removes a key's newest backup, however old" {
			New-TestBackup -Root $script:Root -Category "Config" -Key "K" -Stamp "2020-01-01_00-00-01" -AgeDays 400 | Out-Null

			Clear-OldBackups -BackupRoot $script:Root -MaxAgeDays 7 -MaxBackupsPerKey 0 -MaxTotalSizeMB 0

			Test-Path -Path (Join-Path $script:Root "Config\K\2020-01-01_00-00-01") | Should -Be $true
		}
	}

	Context "Total size limit" {
		It "Removes oldest backups first until the sink is under the cap, keeping every key's newest" {
			# ~1MB each; cap of 2MB forces removals in oldest-first order.
			New-TestBackup -Root $script:Root -Category "Config" -Key "A" -Stamp "2020-01-01_00-00-01" -SizeBytes 1MB | Out-Null
			New-TestBackup -Root $script:Root -Category "Config" -Key "A" -Stamp "2020-01-01_00-00-02" -SizeBytes 1MB | Out-Null
			New-TestBackup -Root $script:Root -Category "Config" -Key "B" -Stamp "2020-01-01_00-00-03" -SizeBytes 1MB | Out-Null

			Clear-OldBackups -BackupRoot $script:Root -MaxTotalSizeMB 2 -MaxAgeDays 0 -MaxBackupsPerKey 0

			Test-Path -Path (Join-Path $script:Root "Config\A\2020-01-01_00-00-01") | Should -Be $false
			Test-Path -Path (Join-Path $script:Root "Config\A\2020-01-01_00-00-02") | Should -Be $true
			Test-Path -Path (Join-Path $script:Root "Config\B\2020-01-01_00-00-03") | Should -Be $true
		}

		It "Never removes a key's newest backup even when the sink stays over the cap" {
			New-TestBackup -Root $script:Root -Category "Config" -Key "A" -Stamp "2020-01-01_00-00-01" -SizeBytes 2MB | Out-Null
			New-TestBackup -Root $script:Root -Category "Config" -Key "B" -Stamp "2020-01-01_00-00-02" -SizeBytes 2MB | Out-Null

			Clear-OldBackups -BackupRoot $script:Root -MaxTotalSizeMB 1 -MaxAgeDays 0 -MaxBackupsPerKey 0

			Test-Path -Path (Join-Path $script:Root "Config\A\2020-01-01_00-00-01") | Should -Be $true
			Test-Path -Path (Join-Path $script:Root "Config\B\2020-01-01_00-00-02") | Should -Be $true
		}
	}

	Context "Housekeeping" {
		It "Removes key and category folders left empty" {
			New-Item -ItemType Directory -Path (Join-Path $script:Root "Config\Empty") -Force | Out-Null
			New-Item -ItemType Directory -Path (Join-Path $script:Root "Hollow") -Force | Out-Null
			New-TestBackup -Root $script:Root -Category "Config" -Key "K" -Stamp "2020-01-01_00-00-01" | Out-Null

			Clear-OldBackups -BackupRoot $script:Root

			Test-Path -Path (Join-Path $script:Root "Config\Empty") | Should -Be $false
			Test-Path -Path (Join-Path $script:Root "Hollow") | Should -Be $false
			Test-Path -Path (Join-Path $script:Root "Config\K") | Should -Be $true
		}

		It "Leaves files at the sink root alone" {
			Set-Content -Path (Join-Path $script:Root ".gitkeep") -Value "" -NoNewline

			Clear-OldBackups -BackupRoot $script:Root

			Test-Path -Path (Join-Path $script:Root ".gitkeep") | Should -Be $true
		}

		It "Returns quietly when the sink does not exist" {
			{ Clear-OldBackups -BackupRoot (Join-Path $TestDrive "NoSuchSink") } | Should -Not -Throw
		}

		It "Ignores folders that are not timestamped backups" {
			New-Item -ItemType Directory -Path (Join-Path $script:Root "Config\K\NotATimestamp") -Force | Out-Null
			New-TestBackup -Root $script:Root -Category "Config" -Key "K" -Stamp "2020-01-01_00-00-01" | Out-Null

			Clear-OldBackups -BackupRoot $script:Root -MaxBackupsPerKey 1

			Test-Path -Path (Join-Path $script:Root "Config\K\NotATimestamp") | Should -Be $true
		}
	}

	Context "Configuration defaults" {
		It "Reads unbound limits from Configuration.Backups.Retention" {
			$global:Configuration = @{ Backups = @{ Retention = @{ MaxAgeDays = 0; MaxBackupsPerKey = 1; MaxTotalSizeMB = 0 } } }
			New-TestBackup -Root $script:Root -Category "Config" -Key "K" -Stamp "2020-01-01_00-00-01" | Out-Null
			New-TestBackup -Root $script:Root -Category "Config" -Key "K" -Stamp "2020-01-01_00-00-02" | Out-Null

			Clear-OldBackups -BackupRoot $script:Root

			$remaining = @(Get-ChildItem -Path (Join-Path $script:Root "Config\K") -Directory)
			$remaining.Name | Should -Be @("2020-01-01_00-00-02")
		}

		It "Uses the documented fallbacks when no configuration is loaded" {
			$global:Configuration = $null
			foreach ($i in 1..12) {
				New-TestBackup -Root $script:Root -Category "Config" -Key "K" -Stamp ("2020-01-01_00-00-{0:d2}" -f $i) | Out-Null
			}

			Clear-OldBackups -BackupRoot $script:Root

			# Fallbacks: MaxAgeDays 0, MaxBackupsPerKey 10, MaxTotalSizeMB 500.
			@(Get-ChildItem -Path (Join-Path $script:Root "Config\K") -Directory).Count | Should -Be 10
		}
	}
}
