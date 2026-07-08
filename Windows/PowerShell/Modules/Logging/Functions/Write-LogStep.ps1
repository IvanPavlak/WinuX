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

	.PARAMETER NoNewLine
		Suppress the trailing newline (for composing a line across multiple calls).

	.PARAMETER NoLeadingNewline
		Suppress the leading "`n".

	.PARAMETER BlankLineAfter
		Emit a blank line after the message (reproduces an original trailing-"`n" spacer). Ignored with -NoNewLine.

	.EXAMPLE
		Write-LogStep "Opening training file..."
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[AllowEmptyString()]
		[string]$Message,

		[Parameter(Mandatory = $false)]
		[switch]$NoNewLine,

		[Parameter(Mandatory = $false)]
		[switch]$NoLeadingNewline,

		[Parameter(Mandatory = $false)]
		[switch]$BlankLineAfter
	)
	Write-Log -Level Step -Message $Message -NoNewLine:$NoNewLine -NoLeadingNewline:$NoLeadingNewline -BlankLineAfter:$BlankLineAfter
}
