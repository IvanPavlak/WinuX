function GitBranchDeleteAndPrune {
	<#
	.SYNOPSIS
		Force-deletes a local branch and prunes stale remote-tracking refs for origin.

	.DESCRIPTION
		Runs `git branch -D <BranchName>` to force-delete the specified local branch,
		then runs `git remote prune origin` to remove any remote-tracking refs that no
		longer exist on the remote.
		Alias: gbd

	.PARAMETER BranchName
		Name of the local branch to delete.

	.EXAMPLE
		GitBranchDeleteAndPrune -BranchName "feature/done"
		Deletes the local "feature/done" branch and prunes stale origin refs.
	#>
	param( [string] $BranchName )

	git branch -D $BranchName
	git remote prune origin
}
