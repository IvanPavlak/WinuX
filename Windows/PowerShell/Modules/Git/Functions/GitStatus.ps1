function GitStatus {
	<#
	.SYNOPSIS
		Shows the working tree status using the configured `git status` arguments.

	.DESCRIPTION
		Runs `git status` with the arguments in `$Configuration.GitStatusArguments`
		(default `--short`). An empty array runs a plain `git status`. Arguments given on
		the call replace the configured ones entirely, so `gs -v -v -u` shows the full diff
		of staged changes and all untracked files. Alias: gs

	.EXAMPLE
		GitStatus
		Runs `git status --short` (or whatever GitStatusArguments is set to).

	.EXAMPLE
		GitStatus -v -v -u
		Runs `git status -v -v -u`, ignoring the configured arguments.
	#>
	# Plain assignments, never `$x = if (...) { @(...) }`: that runs the array through the pipeline and
	# unrolls a one-element list such as @('--short') into a string, and splatting a string on a native
	# command passes one argument per character (`- - s h o r t`), so git never sees `--short`.
	[string[]]$gitArguments = $args
	if ($gitArguments.Count -eq 0) {
		$gitArguments = @(Get-ConfigSetting -Path 'GitStatusArguments' -Default @('--short'))
	}
	& git status @gitArguments
}
