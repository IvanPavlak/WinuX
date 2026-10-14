function Write-LogWarning {
	<#
	.SYNOPSIS
		Writes a warning message in the house style (Yellow): a leading-space indent, no "=> " prefix.

	.DESCRIPTION
		Renders "`n Message" in Yellow and mirrors it to the structured log. Unlike success and
		error messages, warnings carry NO "=> " prefix - the engine indents them by one leading
		space instead. This replaces the repository-wide "Write-Host -ForegroundColor Yellow "`n...""
		idiom. Pass the message text only - the leading newline and the space are added by the engine.

	.PARAMETER Message
		The warning text, WITHOUT a leading newline or "=> " prefix.

	.PARAMETER NoLeadingNewline
		Suppress the leading "`n".

	.PARAMETER BlankLineAfter
		Emit a blank line after the message (reproduces an original trailing-"`n" spacer).

	.EXAMPLE
		Write-LogWarning "No layout configuration found for workspace => [$WorkspaceName]"
		Prints "`n No layout configuration found ..." in Yellow.
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
	Write-Log -Level Warning -Message $Message -NoLeadingNewline:$NoLeadingNewline -BlankLineAfter:$BlankLineAfter
}
