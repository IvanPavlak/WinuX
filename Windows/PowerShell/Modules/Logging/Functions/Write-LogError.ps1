function Write-LogError {
	<#
	.SYNOPSIS
		Writes an error message in the house "=> " style (Red) and records it verbosely to the error log.

	.DESCRIPTION
		Renders "`n=> Message" in Red, mirrors it to the structured session log, and additionally
		appends a verbose entry (message + exception + stack trace, when -Exception is supplied) to
		the shared error log so failures can always be inspected after the fact. This replaces the
		repository-wide "Write-Host -ForegroundColor Red "`n=> ..."" idiom. Pass the message text
		only - the leading newline and "=> " prefix are added by the engine.

	.PARAMETER Message
		The error text, WITHOUT a leading newline or "=> " prefix.

	.PARAMETER Exception
		An ErrorRecord (e.g. $_) or Exception whose message and stack trace are written verbosely
		to the error log.

	.PARAMETER NoLeadingNewline
		Suppress the leading "`n".

	.PARAMETER BlankLineAfter
		Emit a blank line after the message (reproduces an original trailing-"`n" spacer).

	.EXAMPLE
		Write-LogError "Layout configuration file not found => [$LayoutPath]"

	.EXAMPLE
		try { ... } catch { Write-LogError "Error applying workspace layout: $($_.Exception.Message)" -Exception $_ }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[AllowEmptyString()]
		[string]$Message,

		[Parameter(Mandatory = $false)]
		[object]$Exception,

		[Parameter(Mandatory = $false)]
		[switch]$NoLeadingNewline,

		[Parameter(Mandatory = $false)]
		[switch]$BlankLineAfter
	)
	Write-Log -Level Error -Message $Message -Exception $Exception -NoLeadingNewline:$NoLeadingNewline -BlankLineAfter:$BlankLineAfter
}
