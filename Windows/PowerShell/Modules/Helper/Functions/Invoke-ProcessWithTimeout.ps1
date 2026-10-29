function Invoke-ProcessWithTimeout {
	<#
	.SYNOPSIS
		Runs a program with no window, captures its output, and stops it after a time limit.

	.DESCRIPTION
		Starts -FilePath with -ArgumentList through `System.Diagnostics.Process`: no window, no shell,
		stdout and stderr read in memory while it runs. Waits at most -TimeoutSeconds. A process that
		has not exited by then is killed together with its process tree - a shim such as choco.exe
		starts the real program as a child, and killing only the shim would leave that child running.

		Never throws for a slow or failing program; the caller decides what a timeout or a non-zero
		exit code means. Only a program that cannot be started at all throws.

		Starting the process directly rather than through `Start-Process` keeps the cost of a call at
		that of running the command inline: no console window is created and no temporary file is
		written, which matters for a caller that runs it once per app.

	.PARAMETER FilePath
		The program to run, by name on PATH (e.g. "winget") or by full path.

	.PARAMETER ArgumentList
		The arguments, one element per argument. Each is passed as given, quoted where needed.

	.PARAMETER TimeoutSeconds
		Longest wait for the program to exit. Default 60.

	.OUTPUTS
		[pscustomobject] with Output (the non-blank lines of stdout, then stderr), ExitCode (null after
		a timeout) and TimedOut.

	.EXAMPLE
		Invoke-ProcessWithTimeout -FilePath "choco" -ArgumentList "pin", "list", "-r"
		Lists the Chocolatey pins, giving up after 60 seconds.

	.EXAMPLE
		(Invoke-ProcessWithTimeout -FilePath "git" -ArgumentList "fetch" -TimeoutSeconds 10).TimedOut
		True when the fetch was stopped after 10 seconds.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$FilePath,

		[Parameter(Position = 1)]
		[string[]]$ArgumentList = @(),

		[Parameter()]
		[ValidateRange(1, 3600)]
		[int]$TimeoutSeconds = 60
	)

	$startInfo = [System.Diagnostics.ProcessStartInfo]::new($FilePath)
	foreach ($argument in $ArgumentList) { $startInfo.ArgumentList.Add($argument) }
	$startInfo.UseShellExecute = $false
	$startInfo.CreateNoWindow = $true
	$startInfo.RedirectStandardOutput = $true
	$startInfo.RedirectStandardError = $true
	$startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
	$startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

	$process = [System.Diagnostics.Process]::Start($startInfo)
	try {
		# Both streams are drained asynchronously from the start: a program that fills one pipe while
		# nobody reads it blocks forever, which would look exactly like the stall this guards against.
		$stdoutTask = $process.StandardOutput.ReadToEndAsync()
		$stderrTask = $process.StandardError.ReadToEndAsync()

		$timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
		if ($timedOut) {
			try { $process.Kill($true) } catch { Write-LogDebug "Could not stop the timed-out [$FilePath] => $($_.Exception.Message)" -Style Warning }
		}

		# A grandchild that outlives the program can keep a pipe open, so the reads get a short grace
		# period rather than an unbounded wait.
		$null = [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($stdoutTask, $stderrTask), 5000)

		$output = @(
			foreach ($task in @($stdoutTask, $stderrTask)) {
				if ($task.IsCompletedSuccessfully) {
					$task.Result -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
				}
			}
		)

		[pscustomobject]@{
			Output   = $output
			ExitCode = if ($timedOut) { $null } else { $process.ExitCode }
			TimedOut = $timedOut
		}
	}
	finally {
		$process.Dispose()
	}
}
