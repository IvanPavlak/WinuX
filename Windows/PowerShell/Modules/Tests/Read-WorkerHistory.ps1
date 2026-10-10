function Read-WorkerHistory {
	<#
	.SYNOPSIS
		Reads the worker-count history (Results\workers.json) the adaptive worker count learns from.

	.DESCRIPTION
		The file holds one machine fingerprint - "<ProcessorCount>|<full-suite file count rounded
		to the nearest 50>" - the number of runs ever recorded for it, and the most recent runs.
		A full run passes its own fingerprint and gets the runs only when it matches exactly; a
		scoped run cannot know the full suite's file count and passes only -ProcessorCount, which
		matches on the processor part.

		A missing, unreadable or corrupt file, or a fingerprint that does not match, reads as no
		history. This never throws: a broken history must never break a run.

	.PARAMETER Path
		The history file.

	.PARAMETER Fingerprint
		The exact fingerprint to match (full runs).

	.PARAMETER ProcessorCount
		Match only the processor part of the fingerprint (scoped runs).

	.OUTPUTS
		[pscustomobject] Fingerprint (the file's, or $null), Recorded (int), Runs (object[]).

	.EXAMPLE
		Read-WorkerHistory -Path $historyFile -Fingerprint '16|450'
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Path,

		[Parameter()]
		[string]$Fingerprint,

		[Parameter()]
		[int]$ProcessorCount = 0
	)

	$empty = [pscustomobject]@{ Fingerprint = $null; Recorded = 0; Runs = @() }

	try {
		if (-not (Test-Path -LiteralPath $Path)) { return $empty }
		$data = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
		if (-not $data -or -not $data.fingerprint) { return $empty }

		$stored = [string]$data.fingerprint
		$isMatch = $true
		if ($Fingerprint) { $isMatch = $stored -eq $Fingerprint }
		elseif ($ProcessorCount -gt 0) { $isMatch = ($stored -split '\|')[0] -eq [string]$ProcessorCount }
		if (-not $isMatch) { return [pscustomobject]@{ Fingerprint = $stored; Recorded = 0; Runs = @() } }

		$runs = @($data.runs | Where-Object { $_ -and $_.workers -and $_.wallSec })
		return [pscustomobject]@{ Fingerprint = $stored; Recorded = [int]$data.recorded; Runs = $runs }
	}
	catch {
		return $empty
	}
}
