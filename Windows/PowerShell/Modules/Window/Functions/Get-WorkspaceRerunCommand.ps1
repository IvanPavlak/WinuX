function Get-WorkspaceRerunCommand {
	<#
	.SYNOPSIS
		Returns the exact Open-Workspace invocation recorded for the open in progress, or $null.

	.DESCRIPTION
		The read side of Set-WorkspaceRerunCommand. Set-WorkspaceWindowLayout calls it when the
		in-process retries are exhausted and the workspace has to be rerun in a fresh shell: a
		recorded command is handed to ReRun-LastCommand -Command so the respawn reruns precisely
		the open that is failing, and PSReadLine history is never consulted. $null (nothing
		recorded - a standalone Set-WorkspaceWindowLayout call, or an open that already ended)
		lets ReRun-LastCommand fall back to the history prompt as before.

		Module state rather than an environment variable, so a terminal tab spawned by the open
		can never inherit it - see Set-WorkspaceRerunCommand.

	.OUTPUTS
		[string] the recorded command line, or $null.

	.EXAMPLE
		$command = Get-WorkspaceRerunCommand
		if ($command) { ReRun-LastCommand -AutoAccept -Command $command }
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param()

	if ([string]::IsNullOrWhiteSpace($script:WorkspaceRerunCommand)) {
		return $null
	}

	return [string]$script:WorkspaceRerunCommand
}
