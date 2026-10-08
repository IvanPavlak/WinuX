function Write-LogSegments {
	<#
	.SYNOPSIS
		Writes one console line made of differently colored segments, logged as one line.

	.DESCRIPTION
		For a line whose parts carry their own meaning - a totals line where every count has its
		own color, for example. Each segment is a hashtable with Text and an optional Style, a
		palette entry of $Configuration.Logging.Colors: Title, Step, Success, Warning, Error,
		Debug or Info. A segment without a Style, or with an unknown one, is drawn in the Step
		color (White).

		The segments are drawn one after another on the same line, with the house leading
		newline before the first, and the line is mirrored to the session log once, as a STEP
		entry holding the whole text. Visibility follows the Step level: nothing reaches the
		console at the Quiet level, but the file log still gets the line.

	.PARAMETER Segments
		The parts of the line, in order: @{ Text = "..."; Style = "Success" }.

	.PARAMETER NoLeadingNewline
		Suppress the leading "`n".

	.EXAMPLE
		Write-LogSegments @(@{ Text = "=> Totals => " }, @{ Text = "3 passed"; Style = "Success" }, @{ Text = ", " }, @{ Text = "1 failed"; Style = "Error" })
		Prints "=> Totals => 3 passed, 1 failed" with the counts in green and red.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[AllowEmptyCollection()]
		[object[]]$Segments,

		[Parameter(Mandatory = $false)]
		[switch]$NoLeadingNewline
	)

	if ($Segments.Count -eq 0) { return }
	if (-not $global:LoggingState) { Initialize-LoggingState | Out-Null }
	$state = $global:LoggingState

	if ($state.Level -ne "Quiet") {
		$lead = if ($NoLeadingNewline) { "" } else { "`n" }
		for ($i = 0; $i -lt $Segments.Count; $i++) {
			$segment = $Segments[$i]
			$style = if ($segment.Style) { "$($segment.Style)" } else { "Step" }
			$color = $state.Colors[$style]
			if (-not $color) { $color = $state.Colors["Step"] }
			if (-not $color) { $color = "White" }
			$text = if ($i -eq 0) { "$lead$($segment.Text)" } else { "$($segment.Text)" }
			Write-Host -ForegroundColor $color -NoNewline:($i -lt $Segments.Count - 1) -Object $text
		}
	}

	Write-Log -Level Step -Message (-join ($Segments | ForEach-Object { "$($_.Text)" })) -NoConsole
}
