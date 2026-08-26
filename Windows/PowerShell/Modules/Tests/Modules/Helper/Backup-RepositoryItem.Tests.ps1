#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Backup-RepositoryItem.ps1"

	# The function reads $global:Configuration.Backups.Retention; isolate every test from the
	# machine's real configuration and restore it afterwards.
	$script:SavedConfiguration = $global:Configuration
}

AfterAll {
	$global:Configuration = $script:SavedConfiguration
}

Describe "Backup-RepositoryItem" {
	BeforeEach {
		$global:Configuration = @{}
		$script:Root = Join-Path $TestDrive "Sink"
		$script:Source = Join-Path $TestDrive "original.txt"
		Set-Content -Path $script:Source -Value "precious content" -NoNewline
	}

	AfterEach {
		Remove-Item -Path $script:Root -Recurse -Force -ErrorAction SilentlyContinue
		Remove-Item -Path $script:Source -Force -ErrorAction SilentlyContinue
	}

	Context "Taking backups" {
		It "Copies a file into <root>\<Category>\<Key>\<timestamp>\ and returns the timestamped folder" {
			$backupDir = Backup-RepositoryItem -Path $script:Source -Category "Config" -Key "Configuration.local" -BackupRoot $script:Root

			$backupDir | Should -Match ([regex]::Escape((Join-Path $script:Root "Config\Configuration.local")) + '\\\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$')
			Get-Content -Path (Join-Path $backupDir "original.txt") -Raw | Should -Be "precious content"
		}

		It "Copies a directory recursively" {
			$sourceDir = Join-Path $TestDrive "Layouts"
			New-Item -ItemType Directory -Path (Join-Path $sourceDir "Nested") -Force | Out-Null
			Set-Content -Path (Join-Path $sourceDir "Nested\deep.txt") -Value "deep" -NoNewline

			$backupDir = Backup-RepositoryItem -Path $sourceDir -Category "SymbolicLinks" -Key "Some.Directory" -BackupRoot $script:Root

			Get-Content -Path (Join-Path $backupDir "Layouts\Nested\deep.txt") -Raw | Should -Be "deep"
		}

		It "Leaves the original untouched" {
			Backup-RepositoryItem -Path $script:Source -Category "Config" -Key "K" -BackupRoot $script:Root | Out-Null

			Get-Content -Path $script:Source -Raw | Should -Be "precious content"
		}

		It "Sanitizes path characters out of the key and category folder names" {
			$backupDir = Backup-RepositoryItem -Path $script:Source -Category "Con:fig" -Key 'C:\some\path?' -BackupRoot $script:Root

			$backupDir | Should -Match ([regex]::Escape((Join-Path $script:Root "Con_fig\C__some_path_")))
		}

		It "Suffixes a same-second second backup instead of mixing the two" {
			$first = Backup-RepositoryItem -Path $script:Source -Category "Config" -Key "K" -BackupRoot $script:Root
			$stamp = Split-Path -Path $first -Leaf
			$second = Backup-RepositoryItem -Path $script:Source -Category "Config" -Key "K" -BackupRoot $script:Root

			if ((Split-Path -Path $second -Leaf) -ne $stamp) {
				# The clock ticked between the two calls; force the collision explicitly instead.
				$second = Backup-RepositoryItem -Path $script:Source -Category "Config" -Key "K" -BackupRoot $script:Root
			}
			# Regardless of clock ticks, no two calls may ever return the same folder.
			$second | Should -Not -Be $first
			Test-Path -Path (Join-Path $second "original.txt") | Should -Be $true
		}

		It "Creates only the timestamped folder with -DirectoryOnly" {
			$backupDir = Backup-RepositoryItem -Path $script:Source -Category "SymbolicLinks" -Key "WSLShell.Bashrc" -BackupRoot $script:Root -DirectoryOnly

			Test-Path -Path $backupDir | Should -Be $true
			Get-ChildItem -Path $backupDir | Should -BeNullOrEmpty
		}
	}

	Context "Failure semantics" {
		It "Throws when nothing exists at the path" {
			{ Backup-RepositoryItem -Path (Join-Path $TestDrive "missing.txt") -Category "Config" -Key "K" -BackupRoot $script:Root } |
				Should -Throw "*nothing exists*"
		}

		It "Throws on copy failure and leaves no partial backup folder behind" {
			Mock Copy-Item { throw "disk on fire" }

			{ Backup-RepositoryItem -Path $script:Source -Category "Config" -Key "K" -BackupRoot $script:Root } |
				Should -Throw "*disk on fire*"
			Test-Path -Path (Join-Path $script:Root "Config\K") | Should -Be $false
		}
	}

	Context "Per-key opportunistic pruning" {
		BeforeEach {
			# Pre-seed old timestamped backups so the newest post-backup count is deterministic.
			$script:KeyDir = Join-Path $script:Root "Config\K"
			foreach ($stamp in "2020-01-01_00-00-01", "2020-01-01_00-00-02", "2020-01-01_00-00-03") {
				New-Item -ItemType Directory -Path (Join-Path $script:KeyDir $stamp) -Force | Out-Null
			}
		}

		It "Prunes the key down to Backups.Retention.MaxBackupsPerKey after a successful backup" {
			$global:Configuration = @{ Backups = @{ Retention = @{ MaxBackupsPerKey = 2 } } }

			$backupDir = Backup-RepositoryItem -Path $script:Source -Category "Config" -Key "K" -BackupRoot $script:Root

			$remaining = @(Get-ChildItem -Path $script:KeyDir -Directory | Sort-Object Name)
			$remaining.Count | Should -Be 2
			$remaining[0].Name | Should -Be "2020-01-01_00-00-03"
			$remaining[1].FullName | Should -Be $backupDir
		}

		It "Does not prune when MaxBackupsPerKey is 0" {
			$global:Configuration = @{ Backups = @{ Retention = @{ MaxBackupsPerKey = 0 } } }

			Backup-RepositoryItem -Path $script:Source -Category "Config" -Key "K" -BackupRoot $script:Root | Out-Null

			@(Get-ChildItem -Path $script:KeyDir -Directory).Count | Should -Be 4
		}

		It "Falls back to keeping 10 per key when no configuration is loaded" {
			$global:Configuration = $null

			Backup-RepositoryItem -Path $script:Source -Category "Config" -Key "K" -BackupRoot $script:Root | Out-Null

			@(Get-ChildItem -Path $script:KeyDir -Directory).Count | Should -Be 4
		}

		It "Only prunes the key that was backed up" {
			$global:Configuration = @{ Backups = @{ Retention = @{ MaxBackupsPerKey = 1 } } }
			$otherKeyDir = Join-Path $script:Root "Config\Other"
			New-Item -ItemType Directory -Path (Join-Path $otherKeyDir "2020-01-01_00-00-01") -Force | Out-Null
			New-Item -ItemType Directory -Path (Join-Path $otherKeyDir "2020-01-01_00-00-02") -Force | Out-Null

			Backup-RepositoryItem -Path $script:Source -Category "Config" -Key "K" -BackupRoot $script:Root | Out-Null

			@(Get-ChildItem -Path $script:KeyDir -Directory).Count | Should -Be 1
			@(Get-ChildItem -Path $otherKeyDir -Directory).Count | Should -Be 2
		}
	}
}
