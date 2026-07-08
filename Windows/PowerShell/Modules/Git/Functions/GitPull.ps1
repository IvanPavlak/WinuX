function GitPull {
	<#
	.SYNOPSIS
		Pulls the latest changes from the remote for the current branch.

	.DESCRIPTION
		Runs `git pull` and forwards any additional arguments to git.
		Alias: gp

	.EXAMPLE
		GitPull
		Pulls the latest changes from origin for the current branch.
	#>
	& git pull $args
}
