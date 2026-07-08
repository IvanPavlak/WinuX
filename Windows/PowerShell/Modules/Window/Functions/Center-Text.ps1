function Center-Text {
	<#
	.SYNOPSIS
		Centers text within a specified width.

	.DESCRIPTION
		Centers a string by adding padding on both sides to fit within a specified character width.
		If the text is longer than the width, it is truncated to fit.

	.PARAMETER Text
		The text string to center.

	.PARAMETER Width
		The target width in characters.

	.EXAMPLE
		Center-Text -Text "Hello" -Width 20
		# Returns "       Hello        " (centered in 20 characters)

	.EXAMPLE
		Center-Text -Text "VeryLongTextThatExceedsWidth" -Width 10
		# Returns "VeryLongTe" (truncated to 10 characters)

	.OUTPUTS
		String with the centered text.
	#>
	param (
		[Parameter(Mandatory = $true)]
		[string]$Text,

		[Parameter(Mandatory = $true)]
		[int]$Width
	)

	$textLength = $Text.Length
	if ($textLength -ge $Width) {
		return $Text.Substring(0, $Width)
	}
	$padding = $Width - $textLength
	$leftPad = [Math]::Floor($padding / 2)
	$rightPad = $padding - $leftPad
	return (" " * $leftPad) + $Text + (" " * $rightPad)
}
