function Write-LogDebug {
	<#
	.SYNOPSIS
		Writes a verbose-gated diagnostic message (DarkCyan by default).

	.DESCRIPTION
		Renders "`n [Caller] Message" and mirrors it to the structured log. The message prints to the
		console ONLY when verbose logging is active - that is when Set-LogLevel set the session (or a
		scoped command) to Verbose, or when a global $VerbosePreference = 'Continue' is in effect.
		Set-LogLevel is the cross-module-reliable control: set it once (or use the scoped form
		`Set-LogLevel Verbose { Verb-Noun }`) and every function's Write-LogDebug honors it with no
		parameter threading.

		Suppressed debug lines are still written to the file log at full detail, so the file record
		is always complete regardless of console verbosity.

	.PARAMETER Message
		The diagnostic text, WITHOUT a leading newline.

	.PARAMETER Style
		Render the message in another level's color while keeping it verbose-gated (e.g. -Style Success
		for a green diagnostic line). Defaults to the Debug color (DarkCyan).

	.PARAMETER NoLeadingNewline
		Suppress the leading "`n".

	.PARAMETER BlankLineAfter
		Emit a blank line after the message (reproduces an original trailing-"`n" spacer).

	.EXAMPLE
		Write-LogDebug "Captured $($handles.Count) existing window handle(s)"

	.EXAMPLE
		Write-LogDebug "Using machine-specific layout => [$fileName]" -Style Success
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[AllowEmptyString()]
		[string]$Message,

		[Parameter(Mandatory = $false)]
		[ValidateSet("Title", "Step", "Success", "Warning", "Error", "Debug")]
		[string]$Style = "Debug",

		[Parameter(Mandatory = $false)]
		[switch]$NoLeadingNewline,

		[Parameter(Mandatory = $false)]
		[switch]$BlankLineAfter
	)
	Write-Log -Level Debug -Message $Message -Style $Style -NoLeadingNewline:$NoLeadingNewline -BlankLineAfter:$BlankLineAfter
}
