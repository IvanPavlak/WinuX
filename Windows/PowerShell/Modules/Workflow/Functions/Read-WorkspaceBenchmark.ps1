function Read-WorkspaceBenchmark {
	<#
	.SYNOPSIS
		Reads the workspace benchmark file as typed rows, oldest first.

	.DESCRIPTION
		The read side shared by Get-WorkspaceBenchmark and Measure-WorkspaceOpen. Import-Csv yields
		strings; the numbers were written culture-invariant by Write-WorkspaceBenchmark, so they
		parse the same way on every machine. Every seconds column becomes a double and Attempts an
		int; an unparseable cell reads as 0 rather than failing the whole read. Rows come back sorted
		by Timestamp (written as yyyy-MM-dd HH:mm:ss, so a string sort is chronological), with rows
		written within the same second kept in file order.

		A file that does not exist yet reads as an empty result. A file that exists but cannot be
		read throws, so the caller decides how to report it.

	.PARAMETER BenchmarkPath
		Read a different file. Defaults to Get-WorkspaceBenchmarkPath.

	.EXAMPLE
		Read-WorkspaceBenchmark | Where-Object Workspace -eq MyWorkspace | Select-Object -Last 1

	.EXAMPLE
		@(Read-WorkspaceBenchmark -BenchmarkPath $path).Count
		# How many opens have been recorded so far.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter()]
		[string]$BenchmarkPath
	)

	if ([string]::IsNullOrWhiteSpace($BenchmarkPath)) {
		$BenchmarkPath = Get-WorkspaceBenchmarkPath
	}

	if (-not (Test-Path -LiteralPath $BenchmarkPath)) {
		return @()
	}

	$rawRows = @(Import-Csv -LiteralPath $BenchmarkPath -ErrorAction Stop)

	$integerColumns = @('Attempts')
	$secondColumns = @(
		'TotalSeconds', 'ActionsSeconds', 'LayoutSeconds', 'PreambleSeconds', 'DesktopsSeconds',
		'FancyZonesSeconds', 'WaitSeconds', 'NormalizeSeconds', 'PositionSeconds', 'SnapSeconds',
		'VerifySeconds', 'RetrySeconds', 'SaveSeconds', 'OtherSeconds'
	)
	$invariant = [System.Globalization.CultureInfo]::InvariantCulture

	$rows = foreach ($rawRow in $rawRows) {
		$typed = [ordered]@{}
		foreach ($property in $rawRow.PSObject.Properties) {
			$name = $property.Name
			$value = $property.Value

			if ($secondColumns -contains $name -or $integerColumns -contains $name) {
				$parsed = 0.0
				if (-not [double]::TryParse([string]$value, [System.Globalization.NumberStyles]::Float, $invariant, [ref]$parsed)) {
					$parsed = 0.0
				}
				$value = if ($integerColumns -contains $name) { [int]$parsed } else { [double]$parsed }
			}

			$typed[$name] = $value
		}
		[PSCustomObject]$typed
	}

	return @(@($rows) | Sort-Object -Property Timestamp -Stable)
}
