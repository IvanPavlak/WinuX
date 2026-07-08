function GitBranch {
	<#
	.SYNOPSIS
		Creates a new branch or lists all branches when called with no argument.

	.DESCRIPTION
		When called with a branch name, creates that branch with `git branch <name>`.
		When called with no argument, lists all local and remote branches with verbose output
		using `git branch -v -a`.
		Alias: gb

	.PARAMETER BranchName
		Name of the branch to create. Omit to list all branches.

	.EXAMPLE
		GitBranch
		Lists all local and remote branches.

	.EXAMPLE
		GitBranch -BranchName "feature/my-feature"
		Creates a new branch named "feature/my-feature".
	#>
	param(
		[string]$BranchName
	)

	if (-not $BranchName) { git branch -v -a } else { git branch $BranchName }
}
