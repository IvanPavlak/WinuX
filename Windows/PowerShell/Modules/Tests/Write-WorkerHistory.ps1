function Write-WorkerHistory {
	<#
	.SYNOPSIS
		Appends one recorded full run to the worker-count history (Results\workers.json).

	.DESCRIPTION
		Keeps the newest -Keep runs (60 by default) and counts every run ever recorded for the
		fingerprint. A different fingerprint than the one stored - another CPU, or a suite that
		grew or shrank by 50 files or more - restarts learning from this one run. The file is
		written to a temporary name and moved into place, so a concurrent reader never sees half
		of it. Never throws: failing to record a sample must never fail a run.

	.PARAMETER Path
		The history file.

	.PARAMETER Fingerprint
		This run's fingerprint, "<ProcessorCount>|<file count rounded to the nearest 50>".

	.PARAMETER Sample
		The run to record: at least workers and wallSec; any run conditions are stored with it.

	.PARAMETER Keep
		How many runs to keep. Defaults to 60.

	.OUTPUTS
		[bool] Whether the sample was written.

	.EXAMPLE
		Write-WorkerHistory -Path $historyFile -Fingerprint '16|450' -Sample @{ workers = 12; wallSec = 54.6 }
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Path,

		[Parameter(Mandatory = $true)]
		[string]$Fingerprint,

		[Parameter(Mandatory = $true)]
		[object]$Sample,

		[Parameter()]
		[int]$Keep = 60
	)

	try {
		$existing = Read-WorkerHistory -Path $Path -Fingerprint $Fingerprint
		$runs = [System.Collections.Generic.List[object]]::new()
		foreach ($run in @($existing.Runs)) { $runs.Add($run) }
		$runs.Add($Sample)
		while ($runs.Count -gt [Math]::Max(1, $Keep)) { $runs.RemoveAt(0) }

		$document = [ordered]@{
			version     = 1
			fingerprint = $Fingerprint
			recorded    = [int]$existing.Recorded + 1
			runs        = @($runs)
		}

		$directory = Split-Path -Path $Path -Parent
		if ($directory -and -not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
		$temporary = "$Path.$PID.tmp"
		[System.IO.File]::WriteAllText($temporary, ($document | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
		Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
		return $true
	}
	catch {
		return $false
	}
}
