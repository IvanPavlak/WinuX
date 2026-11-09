function Wait-StartupTaskResult {
	<#
	.SYNOPSIS
		Waits for a startup task that runs in another shell, and returns how it ended.

	.DESCRIPTION
		A startup task started in its own tab or hidden shell reports through its result file
		(Logs\.startup-task-<Name>.result, JSON): Invoke-StartupTask writes a Running record with
		the shell's process id once it holds the task's lock, and the final record when the task
		is over. This function reads that file until one of three things happens:

		- A final record is there: its Status and Reason are returned.
		- The record says Running but the shell is gone. The task closed its own shell - a
		  workspace that ends by closing its terminal tab does exactly that - so it counts as
		  finished: the status is Ended, and with -StampFile the task's stamp is written, as
		  after a success.
		- -Timeout seconds pass: the status is TimedOut. Nothing is stopped; the task may still
		  finish later and write its own stamp.

		A record that cannot be read yet (the file is being written) is simply read again.

	.PARAMETER Name
		The task's name, for the returned object.

	.PARAMETER ResultFile
		Full path of the task's result file.

	.PARAMETER Timeout
		Seconds to wait. Default 600; 0 waits without limit.

	.PARAMETER StampFile
		The task's stamp file, written when the task's shell ended without a final record.

	.PARAMETER PollMilliseconds
		How often the result file is read. Default 250.

	.OUTPUTS
		[pscustomobject] with Name, Status, Reason and ResultFile.

	.EXAMPLE
		Wait-StartupTaskResult -Name MyTask -ResultFile $resultFile -Timeout 120
		Waits up to two minutes for MyTask and returns its final status.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter(Mandatory = $true)]
		[string]$ResultFile,

		[Parameter()]
		[double]$Timeout = 600,

		[Parameter()]
		[string]$StampFile,

		[Parameter()]
		[ValidateRange(1, 60000)]
		[int]$PollMilliseconds = 250
	)

	$started = Get-Date
	$status = 'TimedOut'
	$reason = "No result after $([int]$Timeout) s - the task was left running"

	while ($true) {
		$record = $null
		if (Test-Path -LiteralPath $ResultFile) {
			try { $record = Get-Content -LiteralPath $ResultFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $record = $null }
		}

		if ($record -and $record.Status -and $record.Status -ne 'Running') {
			$status = [string]$record.Status
			$reason = [string]$record.Reason
			break
		}

		if ($record -and $record.Status -eq 'Running' -and $record.ProcessId) {
			# Alive means: a process with that id that started when the record says it did. The
			# start time guards against Windows handing the id to another process.
			$alive = $false
			$process = Get-Process -Id ([int]$record.ProcessId) -ErrorAction SilentlyContinue
			if ($process) {
				$alive = $true
				try {
					$recordedTicks = [long]$record.ProcessStartedTicks
					if ($recordedTicks -gt 0 -and [math]::Abs($process.StartTime.ToUniversalTime().Ticks - $recordedTicks) -gt [timespan]::FromSeconds(2).Ticks) { $alive = $false }
				}
				catch { $alive = $true }
			}

			if (-not $alive) {
				$status = 'Ended'
				$reason = "The task's shell closed before it reported a result"
				if ($StampFile) {
					try { Set-Content -LiteralPath $StampFile -Value (Get-Date -Format 'o') -Encoding UTF8 -Force -ErrorAction Stop } catch { }
				}
				break
			}
		}

		if ($Timeout -gt 0 -and ((Get-Date) - $started).TotalSeconds -ge $Timeout) { break }

		Start-Sleep -Milliseconds $PollMilliseconds
	}

	return [pscustomobject]@{
		Name       = $Name
		Status     = $status
		Reason     = $reason
		ResultFile = $ResultFile
	}
}
