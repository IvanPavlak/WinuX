function GitStatus {
	<#
	.SYNOPSIS
		Shows the working tree status with verbose output including untracked files.

	.DESCRIPTION
		Runs `git status -v -v -u` which shows the full diff of staged changes
		(-v -v) and all untracked files (-u). Forwards any additional arguments to git.
		Alias: gs

	.EXAMPLE
		GitStatus
		Displays the full working tree status with staged diffs and untracked files.
	#>
	& git status -v -v -u $args
}
