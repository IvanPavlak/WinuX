function Write-LogTitle {
	<#
	.SYNOPSIS
		Writes a section header in the house "[Title]" style (DarkCyan).

	.DESCRIPTION
		Renders "`n[Message]" in DarkCyan and mirrors it to the structured log. Pass the title
		text only - the brackets and leading newline are added by the engine. This replaces the
		repository-wide "Write-Host -ForegroundColor DarkCyan "`n[Title]"" idiom.

	.PARAMETER Message
		The title text, WITHOUT surrounding brackets or a leading newline.

	.PARAMETER NoLeadingNewline
		Suppress the leading "`n".

	.PARAMETER BlankLineAfter
		Emit a blank line after the title (reproduces an original trailing-"`n" spacer between a header
		and the body that follows it).

	.EXAMPLE
		Write-LogTitle "Kill All"
		Prints "`n[Kill All]" in DarkCyan.

	.EXAMPLE
		Write-LogTitle "Reloading Custom Modules" -BlankLineAfter
		Prints the header followed by a blank line.
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
	Write-Log -Level Title -Message $Message -NoLeadingNewline:$NoLeadingNewline -BlankLineAfter:$BlankLineAfter
}
