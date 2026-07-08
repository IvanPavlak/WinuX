function GitMergeM {
	<#
	.SYNOPSIS
		Merges the default branch (main or master) into the current branch.

	.DESCRIPTION
		Checks whether a "master" or "main" branch exists in the repository (in that order)
		and merges it into the current branch. Reports an error if neither branch is found.
		Alias: gmm

	.EXAMPLE
		GitMergeM
		Merges master or main into the currently checked-out branch.
	#>
	if (BranchExists "master") { git merge master }
	elseif (BranchExists "main") { git merge main }
	else { Write-LogError "Neither 'master' nor 'main' branch exists in this repository!" }
}
