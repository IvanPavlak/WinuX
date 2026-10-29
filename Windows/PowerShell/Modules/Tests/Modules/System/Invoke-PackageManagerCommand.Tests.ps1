#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules

	. "$ModuleRoot\System\Functions\Invoke-PackageManagerCommand.ps1"
	# Dot-sourced so it exists to Mock: the process handling itself is covered by its own tests.
	. "$ModuleRoot\Helper\Functions\Invoke-ProcessWithTimeout.ps1"
}

Describe "Invoke-PackageManagerCommand" {
	BeforeEach {
		# None of the three managers is installed on a CI runner, so how each one resolves is mocked:
		# winget and choco are programs, scoop is a PowerShell script shim.
		Mock Get-Command { [pscustomobject]@{ CommandType = 'Application'; Source = "C:\Tools\$Name.exe" } }
		Mock Get-Command -ParameterFilter { $Name -eq 'scoop' } -MockWith { [pscustomobject]@{ CommandType = 'ExternalScript'; Source = 'C:\scoop\shims\scoop.ps1' } }
	}

	It "runs <Executable> directly with the given arguments and returns its output" -ForEach @(
		@{ PackageManager = 'WinGet'; Executable = 'winget'; Arguments = @('pin', 'list', '--id', 'Git.Git') }
		@{ PackageManager = 'Chocolatey'; Executable = 'choco'; Arguments = @('pin', 'list', '-r') }
	) {
		$expectedFile = $Executable
		$expectedArguments = $Arguments -join ' '
		Mock Invoke-ProcessWithTimeout { [pscustomobject]@{ Output = @('line one', 'line two'); ExitCode = 0; TimedOut = $false } }

		$result = @(Invoke-PackageManagerCommand -PackageManager $PackageManager -Arguments $Arguments)

		Should -Invoke Invoke-ProcessWithTimeout -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq $expectedFile -and ($ArgumentList -join ' ') -eq $expectedArguments -and $TimeoutSeconds -eq 60
		}
		$result | Should -Be @('line one', 'line two')
	}

	It "runs scoop's script shim in a fresh pwsh without the profile, since it cannot be started as a process" {
		Mock Invoke-ProcessWithTimeout { [pscustomobject]@{ Output = @('{"apps":[]}'); ExitCode = 0; TimedOut = $false } }

		$result = @(Invoke-PackageManagerCommand -PackageManager Scoop -Arguments 'hold', 'git')

		Should -Invoke Invoke-ProcessWithTimeout -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq [System.Environment]::ProcessPath -and
			($ArgumentList -join ' ') -eq '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\scoop\shims\scoop.ps1 hold git'
		}
		$result | Should -Be @('{"apps":[]}')
	}

	It "throws when the manager is not installed, starting nothing" {
		Mock Get-Command { }
		Mock Invoke-ProcessWithTimeout { }

		{ Invoke-PackageManagerCommand -PackageManager WinGet -Arguments 'pin', 'list' } | Should -Throw '*not installed*'

		Should -Invoke Invoke-ProcessWithTimeout -Times 0
	}

	It "passes a custom time limit through" {
		Mock Invoke-ProcessWithTimeout { [pscustomobject]@{ Output = @(); ExitCode = 0; TimedOut = $false } }

		Invoke-PackageManagerCommand -PackageManager Chocolatey -Arguments 'pin', 'list', '-r' -TimeoutSeconds 5 | Out-Null

		Should -Invoke Invoke-ProcessWithTimeout -Times 1 -Exactly -ParameterFilter { $TimeoutSeconds -eq 5 }
	}

	It "throws when the call timed out, so a stall never reads as an empty answer" {
		Mock Invoke-ProcessWithTimeout { [pscustomobject]@{ Output = @(); ExitCode = $null; TimedOut = $true } }

		{ Invoke-PackageManagerCommand -PackageManager Chocolatey -Arguments 'pin', 'list', '-r' } | Should -Throw '*did not finish within 60 s*'
	}

	It "returns the output of a call that failed with a non-zero exit code and leaves the code in LASTEXITCODE" {
		# A refusal is an answer the caller reads (e.g. winget reporting no installed package); only a
		# stall throws.
		Mock Invoke-ProcessWithTimeout { [pscustomobject]@{ Output = @('No installed package found.'); ExitCode = 1; TimedOut = $false } }

		$result = @(Invoke-PackageManagerCommand -PackageManager WinGet -Arguments 'list', '--id', 'Git.Git')

		$result | Should -Be @('No installed package found.')
		$LASTEXITCODE | Should -Be 1
	}
}
