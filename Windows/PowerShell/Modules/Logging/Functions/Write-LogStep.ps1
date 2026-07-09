function Write-LogStep {
	<#
	.SYNOPSIS
		Writes a plain step/progress statement (White).

	.DESCRIPTION
		Renders "`nMessage" in White and mirrors it to the structured log. This replaces the
		repository-wide "Write-Host -ForegroundColor White "`n..."" idiom for ordinary progress
		and descriptive output. Leading-space indentation in the message is preserved, so nested
		sub-steps keep their alignment.

	.PARAMETER Message
		The statement text. Include any intended leading-space indentation; omit the leading "`n".

	.PARAMETER Style
		Render the step in another level's color while keeping the plain Step layout, visibility,
		and STEP file-log tag (e.g. -Style Success for a green outcome row, -Style Error for a red
		one). Defaults to the Step color (White).

	.PARAMETER NoNewLine
		Suppress the trailing newline (for composing a line across multiple calls).

	.PARAMETER NoLeadingNewline
		Suppress the leading "`n".

	.PARAMETER BlankLineAfter
		Emit a blank line after the message (reproduces an original trailing-"`n" spacer). Ignored with -NoNewLine.

	.EXAMPLE
		Write-LogStep "Opening training file..."

	.EXAMPLE
		Write-LogStep " SmoothEdgesOfScreenFonts => [enabled]" -Style Success
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[AllowEmptyString()]
		[string]$Message,

		[Parameter(Mandatory = $false)]
		[ValidateSet("Title", "Step", "Success", "Warning", "Error", "Debug")]
		[string]$Style = "Step",

		[Parameter(Mandatory = $false)]
		[switch]$NoNewLine,

		[Parameter(Mandatory = $false)]
		[switch]$NoLeadingNewline,

		[Parameter(Mandatory = $false)]
		[switch]$BlankLineAfter
	)
	Write-Log -Level Step -Message $Message -Style $Style -NoNewLine:$NoNewLine -NoLeadingNewline:$NoLeadingNewline -BlankLineAfter:$BlankLineAfter
}
