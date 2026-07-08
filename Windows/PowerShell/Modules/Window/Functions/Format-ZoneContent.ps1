function Format-ZoneContent {
	<#
	.SYNOPSIS
		Formats zone content to fit within a specified width.

	.DESCRIPTION
		Formats an array of content items (process names, window titles) to fit within
		a specified character width. Handles multi-line content and truncates long lines
		with an ellipsis character.

	.PARAMETER Content
		Array of content items to format.

	.PARAMETER Width
		Maximum width in characters for each line.

	.EXAMPLE
		Format-ZoneContent -Content @("ProcessName", "WindowTitle") -Width 16

	.OUTPUTS
		Array of formatted strings.
	#>
	param (
		[array]$Content,
		[int]$Width
	)

	$lines = @()
	foreach ($item in $Content) {
		# Ensure item is a string
		$itemStr = [string]$item

		# Split by newlines first (for WindowTitle)
		$itemLines = $itemStr -split "`n"
		foreach ($line in $itemLines) {
			$lineStr = [string]$line
			if ($lineStr.Length -le $Width) {
				$lines += $lineStr
			}
			else {
				# Truncate with ellipsis
				$lines += $lineStr.Substring(0, $Width - 1) + "…"
			}
		}
	}

	# Ensure we always return an array, even with a single element
	return , $lines
}
