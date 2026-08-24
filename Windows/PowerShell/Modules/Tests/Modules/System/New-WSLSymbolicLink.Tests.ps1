#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\New-WSLSymbolicLink.ps1"
}

Describe "New-WSLSymbolicLink" {
	BeforeEach {
		# Control flow is driven by $LASTEXITCODE after every wsl call; pin it to
		# success so the mock is deterministic regardless of prior commands.
		Mock wsl { $global:LASTEXITCODE = 0 }
		Mock Write-Host { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }

		$script:BackupRoot = Join-Path $TestDrive "Backups"
	}

	It "targets the given distribution on every wsl call" {
		{ New-WSLSymbolicLink -Path "/home/test/.ssh/config" -Target "/mnt/c/ssh/config" -Distribution "Ubuntu" } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { ($args -join ' ') -notmatch '-d Ubuntu' } -Times 0
		Should -Invoke wsl -ParameterFilter { $args -contains 'ln' } -Times 1 -Exactly
	}

	It "removes a pre-existing symlink before linking, without backing it up" {
		# The all-success mock reports the existing item as a symlink (`test -L` succeeds), which
		# carries no content of its own - archiving it would pile up copies of WinuX's own link.
		{ New-WSLSymbolicLink -Path "/home/test/link" -Target "/mnt/c/target" -Distribution "Ubuntu" `
				-BackupRoot $script:BackupRoot } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { $args -contains 'rm' } -Times 1 -Exactly
		Should -Invoke wsl -ParameterFilter { $args -contains 'cp' } -Times 0
		Should -Invoke wsl -ParameterFilter { $args -contains 'ln' } -Times 1 -Exactly
		Test-Path -LiteralPath $script:BackupRoot | Should -BeFalse
	}

	It "copies a real file out to the backup root before removing it" {
		Mock wsl {
			$global:LASTEXITCODE = 0
			# `test -L <path>` on its own (no -o) is the is-this-a-symlink probe: fail it so the
			# existing item counts as a REAL file. The combined `test -L ... -o -f ...` existence
			# probe still succeeds, so the item is found.
			if (($args -contains 'test') -and ($args -contains '-L') -and ($args -notcontains '-o')) {
				$global:LASTEXITCODE = 1
			}
			if ($args -contains 'wslpath') { return "/mnt/c/backup" }
		}

		{ New-WSLSymbolicLink -Path "/home/test/.bashrc" -Target "/mnt/c/bashrc" -Distribution "Ubuntu" `
				-DisplayName "WSLShell.Bashrc" -BackupRoot $script:BackupRoot } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { $args -contains 'cp' } -Times 1 -Exactly
		Should -Invoke wsl -ParameterFilter { $args -contains 'rm' } -Times 1 -Exactly
		Should -Invoke wsl -ParameterFilter { $args -contains 'ln' } -Times 1 -Exactly

		# The Windows-side destination folder is created before the in-distro copy runs.
		(Get-ChildItem -Path $script:BackupRoot -Recurse -Directory).FullName | Should -Match "WSLShell\.Bashrc"
	}

	It "keeps the original and skips the link when the backup copy fails" {
		Mock wsl {
			$global:LASTEXITCODE = 0
			if (($args -contains 'test') -and ($args -contains '-L') -and ($args -notcontains '-o')) {
				$global:LASTEXITCODE = 1
			}
			if ($args -contains 'wslpath') { return "/mnt/c/backup" }
			if ($args -contains 'cp') { $global:LASTEXITCODE = 1 }
		}

		{ New-WSLSymbolicLink -Path "/home/test/.bashrc" -Target "/mnt/c/bashrc" -Distribution "Ubuntu" `
				-BackupRoot $script:BackupRoot } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { $args -contains 'rm' } -Times 0
		Should -Invoke wsl -ParameterFilter { $args -contains 'ln' } -Times 0
		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -match "could not back up" }
	}

	It "skips the link when the backup folder cannot be translated for the distribution" {
		Mock wsl {
			$global:LASTEXITCODE = 0
			if (($args -contains 'test') -and ($args -contains '-L') -and ($args -notcontains '-o')) {
				$global:LASTEXITCODE = 1
			}
			if ($args -contains 'wslpath') { $global:LASTEXITCODE = 1; return "" }
		}

		{ New-WSLSymbolicLink -Path "/home/test/.bashrc" -Target "/mnt/c/bashrc" -Distribution "Ubuntu" `
				-BackupRoot $script:BackupRoot } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { $args -contains 'rm' } -Times 0
		Should -Invoke wsl -ParameterFilter { $args -contains 'ln' } -Times 0
		Should -Invoke Write-LogError -Times 1 -ParameterFilter { $Message -match "could not translate" }
	}

	It "skips with a warning when the target does not exist" {
		Mock wsl { $global:LASTEXITCODE = if ($args -contains 'test') { 1 } else { 0 } }

		{ New-WSLSymbolicLink -Path "/home/test/link" -Target "/mnt/c/missing" -Distribution "Ubuntu" } | Should -Not -Throw

		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "target does not exist" }
		Should -Invoke wsl -ParameterFilter { $args -contains 'ln' } -Times 0
	}

	It "creates the parent directory when missing" {
		Mock wsl {
			$global:LASTEXITCODE = if (($args -contains 'test') -and ($args -contains '-d') -and ($args -notcontains '-e')) {
				# `test -d <parent>` fails => parent missing (`-d Ubuntu` is also in $args,
				# so the -e/-L probes are told apart by their own flags)
				if ($args -contains '-L') { 0 } else { 1 }
			}
			else { 0 }
		}

		{ New-WSLSymbolicLink -Path "/home/test/dir/link" -Target "/mnt/c/target" -Distribution "Ubuntu" } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { $args -contains 'mkdir' } -Times 1 -Exactly
	}
}
