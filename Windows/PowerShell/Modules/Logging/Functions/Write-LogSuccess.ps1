function Write-LogSuccess {
	<#
	.SYNOPSIS
		Writes a success message in the house "=> " style (Green).

	.DESCRIPTION
		Renders "`n=> Message" in Green and mirrors it to the structured log. This replaces the
		repository-wide "Write-Host -ForegroundColor Green "`n=> ..."" idiom. Pass the message
		text only - the leading newline and "=> " prefix are added by the engine.

	.PARAMETER Message
		The success text, WITHOUT a leading newline or "=> " prefix.

	.PARAMETER NoLeadingNewline
		Suppress the leading "`n".

	.PARAMETER BlankLineAfter
		Emit a blank line after the message (reproduces an original trailing-"`n" spacer).

	.EXAMPLE
		Write-LogSuccess "Kill All finished successfully!"
		Prints "`n=> Kill All finished successfully!" in Green.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[AllowEmptyString()]
		[string]$Message,

		[Parameter(Mandatory = $false)]
		[switch]$NoLeadingNewline,

		[Parameter(Mandatory = $false)]
		[switch]$BlankLineAfter
	)
	Write-Log -Level Success -Message $Message -NoLeadingNewline:$NoLeadingNewline -BlankLineAfter:$BlankLineAfter
}
