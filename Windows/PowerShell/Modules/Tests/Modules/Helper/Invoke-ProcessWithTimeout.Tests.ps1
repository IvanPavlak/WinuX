#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Invoke-ProcessWithTimeout.ps1"

	# The real processes these tests start: the PowerShell running the suite, so nothing else has to
	# be installed.
	$script:Pwsh = (Get-Process -Id $PID).Path
}

# Real processes and real waits: the whole point is how a live child process is read and stopped,
# which no mock can show.
Describe "Invoke-ProcessWithTimeout" -Tag 'Integration' {
	BeforeEach {
		Mock Write-LogDebug { }
	}

	It "returns stdout then stderr without blank lines, the exit code, and no timeout" {
		$result = Invoke-ProcessWithTimeout -FilePath $script:Pwsh -ArgumentList '-NoProfile', '-NonInteractive', '-Command', "[Console]::Out.WriteLine('first'); [Console]::Out.WriteLine(''); [Console]::Error.WriteLine('problem'); [Console]::Out.WriteLine('second'); exit 3"

		$result.Output | Should -Be @('first', 'second', 'problem')
		$result.ExitCode | Should -Be 3
		$result.TimedOut | Should -BeFalse
	}

	It "stops a process that outlives the timeout, its child processes included" {
		# The parent starts a child that would sleep for a minute and reports its PID before sleeping
		# itself - the shape of choco.exe, a shim whose real work runs in a child.
		$command = "`$child = Start-Process -FilePath '$($script:Pwsh)' -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 60' -NoNewWindow -PassThru; [Console]::Out.WriteLine(`$child.Id); [Console]::Out.Flush(); Start-Sleep -Seconds 60"
		$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

		$result = Invoke-ProcessWithTimeout -FilePath $script:Pwsh -ArgumentList '-NoProfile', '-NonInteractive', '-Command', $command -TimeoutSeconds 3

		$stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 20
		$result.TimedOut | Should -BeTrue
		$result.ExitCode | Should -BeNullOrEmpty

		$childId = [int]($result.Output | Select-Object -First 1)
		$childId | Should -BeGreaterThan 0
		Start-Sleep -Milliseconds 500
		Get-Process -Id $childId -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
	}

	It "throws when the program cannot be started" {
		{ Invoke-ProcessWithTimeout -FilePath 'winux-no-such-program-anywhere' -ArgumentList 'pin', 'list' } | Should -Throw
	}
}
