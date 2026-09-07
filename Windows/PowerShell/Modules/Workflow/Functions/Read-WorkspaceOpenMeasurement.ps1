function Read-WorkspaceOpenMeasurement {
	<#
	.SYNOPSIS
		Reads the experiment result file as typed rows, session by session in the order the opens ran.

	.DESCRIPTION
		The read side shared by Get-WorkspaceOpenMeasurement and anyone who wants the raw rows
		Measure-WorkspaceOpen wrote. Import-Csv yields strings; the numbers were written
		culture-invariant, so they parse the same way on every machine. Every seconds column
		becomes a double, Round, Position and Attempts become ints and Measured a bool; an
		unparseable cell reads as 0 (or $false) rather than failing the whole read. Rows come back
		sorted by Session, then Position - the order the opens ran in.

		A file that does not exist yet reads as an empty result. A file that exists but cannot be
		read throws, so the caller decides how to report it.

	.PARAMETER Session
		Keep only the rows of these session ids. Omit for every session.

	.PARAMETER ResultPath
		Read a different file. Defaults to Get-WorkspaceOpenMeasurementPath.

	.EXAMPLE
		Read-WorkspaceOpenMeasurement -Session 20260907-135804 | Format-Table Variant, Round, Outcome, TotalSeconds

	.EXAMPLE
		Read-WorkspaceOpenMeasurement | Group-Object Session | Select-Object Name, Count
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Position = 0)]
		[string[]]$Session,

		[Parameter()]
		[string]$ResultPath
	)

	if ([string]::IsNullOrWhiteSpace($ResultPath)) {
		$ResultPath = Get-WorkspaceOpenMeasurementPath
	}

	if (-not (Test-Path -LiteralPath $ResultPath)) {
		return @()
	}

	$rawRows = @(Import-Csv -LiteralPath $ResultPath -ErrorAction Stop)

	$integerColumns = @('Round', 'Position', 'Attempts')
	$booleanColumns = @('Measured')
	$invariant = [System.Globalization.CultureInfo]::InvariantCulture

	$rows = foreach ($rawRow in $rawRows) {
		$typed = [ordered]@{}
		foreach ($property in $rawRow.PSObject.Properties) {
			$name = $property.Name
			$value = $property.Value

			if ($name -like '*Seconds' -or $integerColumns -contains $name) {
				$parsed = 0.0
				if (-not [double]::TryParse([string]$value, [System.Globalization.NumberStyles]::Float, $invariant, [ref]$parsed)) {
					$parsed = 0.0
				}
				$value = if ($integerColumns -contains $name) { [int]$parsed } else { [double]$parsed }
			}
			elseif ($booleanColumns -contains $name) {
				$value = ([string]$value).Trim() -ieq 'True'
			}

			$typed[$name] = $value
		}
		[PSCustomObject]$typed
	}
	$rows = @($rows)

	if ($Session) {
		$rows = @($rows | Where-Object { $Session -contains $_.Session })
	}

	return @($rows | Sort-Object -Property Session, Position -Stable)
}
