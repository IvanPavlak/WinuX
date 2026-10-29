function Invoke-PackageManagerCommand {
	<#
	.SYNOPSIS
		Runs one short winget, scoop or choco command with a time limit and returns its output lines.

	.DESCRIPTION
		Runs `<manager> <Arguments>` through `Invoke-ProcessWithTimeout` and waits for it for at most
		-TimeoutSeconds. Meant for the short, query-style calls - pin and hold reads and writes,
		presence checks, `scoop export` - that a healthy manager answers in a second or two. choco has
		been seen to stall inside `choco pin list` with no output and no exit, and winget has stalled on
		a prompt nobody could answer. With nothing to stop such a call the whole unattended
		`Upgrade-All` - and with it Bootstrap - stalled behind it until the session was killed. A call
		that has not exited by the deadline is now killed with its process tree and answered with a
		terminating error, so the caller can stop instead of waiting forever.

		Throwing rather than returning nothing is deliberate: an empty answer from a pin listing would
		read as "no pins", and a pin that never landed would let the next upgrade walk past a version
		lock. Neither may pass for success.

		Long-running work - installs and the bulk upgrades - does not go through here: a large upgrade
		legitimately takes many minutes, and no limit would fit it.

		The three managers are driven the same way; only how each one is started differs. winget and
		choco are programs and are started directly. scoop is a PowerShell script shim (`scoop.ps1`),
		which a process cannot be started from, so it runs in a fresh `pwsh -NoProfile` process - the
		way scoop's own `scoop.cmd` shim runs it.

		The exit code is left in `$LASTEXITCODE`, as after an inline call. A non-zero exit code is not
		an error here: the output is returned for the caller to read.

	.PARAMETER PackageManager
		Which manager to run: "WinGet" (winget), "Scoop" (scoop) or "Chocolatey" (choco).

	.PARAMETER Arguments
		The sub-command and its options, e.g. @("pin", "list", "-r") or @("hold", "git").

	.PARAMETER TimeoutSeconds
		Longest wait for the command to exit. Default 60 - a healthy call takes a second or two, so the
		limit only ever ends a stalled call.

	.OUTPUTS
		[string[]] The command's output lines (stdout, then stderr, blank lines dropped).

	.EXAMPLE
		Invoke-PackageManagerCommand -PackageManager Chocolatey -Arguments "pin", "list", "-r"
		Returns every Chocolatey pin as a "name|version" line.

	.EXAMPLE
		Invoke-PackageManagerCommand -PackageManager Scoop -Arguments "hold", "git"
		Holds git in scoop, giving up after 60 seconds.

	.EXAMPLE
		Invoke-PackageManagerCommand -PackageManager WinGet -Arguments "pin", "add", "--id", "Git.Git", "--blocking" -TimeoutSeconds 30
		Pins Git.Git in winget, giving up after 30 seconds.
	#>
	[CmdletBinding()]
	[OutputType([string[]])]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateSet('WinGet', 'Scoop', 'Chocolatey')]
		[string]$PackageManager,

		[Parameter(Mandatory = $true, Position = 1)]
		[string[]]$Arguments,

		[Parameter()]
		[ValidateRange(1, 3600)]
		[int]$TimeoutSeconds = 60
	)

	$executable = @{ WinGet = 'winget'; Scoop = 'scoop'; Chocolatey = 'choco' }[$PackageManager]

	$command = Get-Command $executable -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
	if (-not $command) {
		throw "[$executable] is not installed on this machine"
	}

	# A script shim cannot be started as a process of its own, so it runs in a fresh pwsh, without
	# the profile; the execution policy is bypassed for that one process, as scoop.cmd does.
	if ("$($command.CommandType)" -eq 'ExternalScript') {
		$filePath = [System.Environment]::ProcessPath
		$argumentList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $command.Source) + $Arguments
	}
	else {
		$filePath = $executable
		$argumentList = $Arguments
	}

	$result = Invoke-ProcessWithTimeout -FilePath $filePath -ArgumentList $argumentList -TimeoutSeconds $TimeoutSeconds

	if ($result.TimedOut) {
		throw "[$executable $($Arguments -join ' ')] did not finish within $TimeoutSeconds s and was stopped"
	}

	$global:LASTEXITCODE = $result.ExitCode
	$result.Output
}
