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
		Mock Write-LogWarning { }
		Mock Write-LogError { }
	}

	It "targets the given distribution on every wsl call" {
		{ New-WSLSymbolicLink -Path "/home/test/.ssh/config" -Target "/mnt/c/ssh/config" -Distribution "Ubuntu" } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { ($args -join ' ') -notmatch '-d Ubuntu' } -Times 0
		Should -Invoke wsl -ParameterFilter { $args -contains 'ln' } -Times 1 -Exactly
	}

	It "removes a pre-existing item before linking" {
		{ New-WSLSymbolicLink -Path "/home/test/link" -Target "/mnt/c/target" -Distribution "Ubuntu" } | Should -Not -Throw

		Should -Invoke wsl -ParameterFilter { $args -contains 'rm' } -Times 1 -Exactly
		Should -Invoke wsl -ParameterFilter { $args -contains 'ln' } -Times 1 -Exactly
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
