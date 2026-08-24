#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\New-WindowsSymbolicLink.ps1"
}

Describe "New-WindowsSymbolicLink" {
	BeforeEach {
		# Only the symlink creation itself is mocked - it needs elevation or Developer Mode,
		# which a test run cannot assume. Everything else (the existence probe, the backup
		# copy, the removal) runs for real against TestDrive, so the backup behavior is
		# verified on actual files rather than on mock bookkeeping.
		Mock New-Item -ParameterFilter { $ItemType -eq 'SymbolicLink' } -MockWith { }
		Mock Initialize-Directory { }
		Mock Write-Host { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }

		$script:LinkPath = Join-Path $TestDrive "link.txt"
		$script:TargetPath = Join-Path $TestDrive "target.txt"
		$script:BackupRoot = Join-Path $TestDrive "Backups"
		Set-Content -Path $script:TargetPath -Value "target" -NoNewline
	}

	It "backs up a real file into the backup root before replacing it" {
		Set-Content -Path $script:LinkPath -Value "original user content" -NoNewline

		New-WindowsSymbolicLink -Path $script:LinkPath -Target $script:TargetPath `
			-DisplayName "PowerShell.Profile" -BackupRoot $script:BackupRoot

		$backup = @(Get-ChildItem -Path $script:BackupRoot -Recurse -File)
		$backup.Count | Should -Be 1
		$backup[0].Name | Should -Be "link.txt"
		Get-Content -Path $backup[0].FullName -Raw | Should -Be "original user content"

		# The backup is filed under the entry key, so a replaced file is findable by the
		# name of the link that replaced it rather than by its own path.
		$backup[0].FullName | Should -Match "PowerShell\.Profile"

		Test-Path -LiteralPath $script:LinkPath | Should -BeFalse
		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { $ItemType -eq 'SymbolicLink' }
	}

	It "backs up a real directory and removes it recursively" {
		$dir = Join-Path $TestDrive "linkdir"
		New-Item -ItemType Directory -Path $dir | Out-Null
		Set-Content -Path (Join-Path $dir "nested.txt") -Value "nested" -NoNewline

		New-WindowsSymbolicLink -Path $dir -Target $script:TargetPath `
			-DisplayName "Some.Folder" -BackupRoot $script:BackupRoot

		$backup = @(Get-ChildItem -Path $script:BackupRoot -Recurse -File)
		$backup.Count | Should -Be 1
		$backup[0].Name | Should -Be "nested.txt"

		Test-Path -LiteralPath $dir | Should -BeFalse
		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { $ItemType -eq 'SymbolicLink' }
	}

	It "does not back up an existing symlink" {
		# A link left by a previous run carries no content of its own. Backing it up would
		# archive a fresh copy of WinuX's own link on every single re-run.
		Set-Content -Path $script:LinkPath -Value "placeholder" -NoNewline
		Mock Get-Item { [pscustomobject]@{ Attributes = [System.IO.FileAttributes]::ReparsePoint; PSIsContainer = $false } }

		New-WindowsSymbolicLink -Path $script:LinkPath -Target $script:TargetPath `
			-DisplayName "PowerShell.Profile" -BackupRoot $script:BackupRoot

		Test-Path -LiteralPath $script:BackupRoot | Should -BeFalse
		Test-Path -LiteralPath $script:LinkPath | Should -BeFalse
		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { $ItemType -eq 'SymbolicLink' }
	}

	It "keeps the original and skips the link when the backup cannot be written" {
		Set-Content -Path $script:LinkPath -Value "irreplaceable" -NoNewline
		Mock Copy-Item { throw "access denied" }

		New-WindowsSymbolicLink -Path $script:LinkPath -Target $script:TargetPath `
			-DisplayName "PowerShell.Profile" -BackupRoot $script:BackupRoot

		Get-Content -Path $script:LinkPath -Raw | Should -Be "irreplaceable"
		Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq 'SymbolicLink' }
		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -match "could not back up" }
	}

	It "creates the link without a backup when nothing exists at the path" {
		New-WindowsSymbolicLink -Path $script:LinkPath -Target $script:TargetPath -BackupRoot $script:BackupRoot

		Test-Path -LiteralPath $script:BackupRoot | Should -BeFalse
		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { $ItemType -eq 'SymbolicLink' }
	}

	It "skips with a warning when the target does not exist" {
		Set-Content -Path $script:LinkPath -Value "original" -NoNewline

		New-WindowsSymbolicLink -Path $script:LinkPath -Target (Join-Path $TestDrive "missing.txt") `
			-BackupRoot $script:BackupRoot

		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "target does not exist" }
		Should -Invoke New-Item -Times 0 -ParameterFilter { $ItemType -eq 'SymbolicLink' }
		# Nothing may be touched when the entry is skipped - not the existing file, not a backup.
		Get-Content -Path $script:LinkPath -Raw | Should -Be "original"
		Test-Path -LiteralPath $script:BackupRoot | Should -BeFalse
	}

	It "creates the parent directory when missing" {
		$nested = Join-Path $TestDrive "parent\link.txt"

		New-WindowsSymbolicLink -Path $nested -Target $script:TargetPath -BackupRoot $script:BackupRoot

		Should -Invoke Initialize-Directory -Times 1 -Exactly
		Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { $ItemType -eq 'SymbolicLink' }
	}

	It "logs an error instead of throwing when creation fails" {
		Mock New-Item -ParameterFilter { $ItemType -eq 'SymbolicLink' } -MockWith { throw "access denied" }

		{ New-WindowsSymbolicLink -Path $script:LinkPath -Target $script:TargetPath -DisplayName "Git" `
				-BackupRoot $script:BackupRoot } | Should -Not -Throw

		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -match "Git" }
	}
}
