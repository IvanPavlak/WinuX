function Create-CenteredBorder {
	<#
        .SYNOPSIS
            Create a centered border line with optional title.

        .DESCRIPTION
            Generates a decorative border string centered to console width with optional title.
            Useful for section headers in CLI output. Falls back to 120 char width if console width unavailable.

        .PARAMETER Title
            Optional text to center in the border (wrapped in brackets).

        .PARAMETER BorderChar
            Character to use for border (default: '=').

        .EXAMPLE
            Create-CenteredBorder -Title "Main Menu" -BorderChar "="
            # Output: ===================== [Main Menu] =====================
        #>
	param (
		[string]$Title = "",
		[char]$BorderChar = "="
	)

	try {
		[int]$Width = $Host.UI.RawUI.WindowSize.Width
	}
 catch {
		[int]$Width = 120  # Fallback
	}

	if ($Title) {
		$titleWithSpaces = " [$Title] "
		[int]$titleLength = $titleWithSpaces.Length
		[int]$remainingWidth = $Width - $titleLength
		[int]$leftPadding = [Math]::Floor($remainingWidth / 2)
		[int]$rightPadding = $remainingWidth - $leftPadding

		return ($BorderChar.ToString() * $leftPadding) + $titleWithSpaces + ($BorderChar.ToString() * $rightPadding)
	}
 else {
		return $BorderChar.ToString() * $Width
	}
}
