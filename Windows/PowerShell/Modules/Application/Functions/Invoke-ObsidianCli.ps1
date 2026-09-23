function Invoke-ObsidianCli {
	<#
	.SYNOPSIS
		Runs one Obsidian CLI command. Isolated so tests can observe the exact invocation.

	.DESCRIPTION
		Waits for Obsidian.com for at most -TimeoutSeconds. A call that has not exited by then is
		killed (with its process tree) and answered with a "CLI call timed out" line, so a CLI that
		never hears back from Obsidian can no longer stall the caller - and with it a whole
		workspace open - indefinitely. A healthy call returns in 0.1 - 1 s against a running
		Obsidian and in a few seconds while Obsidian is still booting; the timeout is only the
		safety net and never delays an answer.

	.PARAMETER TimeoutSeconds
		Longest wait for the CLI to exit. Default 5 - every answer from a running Obsidian arrives
		in under 1 s; only a load sent while Obsidian is still booting takes longer, and Obsidian
		still applies a load it has received after the call is killed.
	#>
	[CmdletBinding()]
	[OutputType([object[]])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$CliPath,

		[Parameter(Mandatory = $true)]
		[string[]]$Arguments,

		[Parameter()]
		[ValidateRange(0.1, 600)]
		[double]$TimeoutSeconds = 5
	)

	Write-LogDebug " [Open-Obsidian] obsidian $($Arguments -join ' ')" -Style Success

	# Obsidian.com writes its chatter (argv echo, callback URL, update check) straight to the
	# console it is attached to, past any stream redirection - so give it a hidden console of
	# its own and read the answer back from files.
	$stdoutFile = [System.IO.Path]::GetTempFileName()
	$stderrFile = [System.IO.Path]::GetTempFileName()
	$timedOut = $false
	try {
		$process = Start-Process -FilePath $CliPath -ArgumentList $Arguments -WindowStyle Hidden -PassThru `
			-RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -ErrorAction Stop
		if ($process -and -not $process.WaitForExit([int]($TimeoutSeconds * 1000))) {
			$timedOut = $true
			try { $process.Kill($true) } catch { Write-LogDebug " [Open-Obsidian] Could not stop the timed-out CLI => $($_.Exception.Message)" -Style Warning }
		}
		$output = @(
			if ($timedOut) { "CLI call timed out after $TimeoutSeconds s" }
			foreach ($file in @($stdoutFile, $stderrFile)) {
				if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } }
			}
		)
	}
	catch {
		Write-LogDebug " [Open-Obsidian] CLI call failed => $($_.Exception.Message)" -Style Warning
		$output = @("CLI call failed: $($_.Exception.Message)")
	}
	finally {
		Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
	}

	foreach ($line in $output) { Write-LogDebug " [Open-Obsidian] $line" }
	return $output
}
