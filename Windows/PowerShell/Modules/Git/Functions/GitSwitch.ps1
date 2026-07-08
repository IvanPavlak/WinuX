function GitSwitch {
	<#
	.SYNOPSIS
		Switches to the specified branch, or to main/master when called with no argument.

	.DESCRIPTION
		When called with a branch name, switches to that branch using `git switch`.
		If the branch does not exist, reports an error.

		When called with no argument, switches to "master" if it exists, otherwise to "main".
		Reports an error if neither default branch is found.
		Alias: gsw

	.PARAMETER BranchName
		Name of the branch to switch to. Omit to switch to the default branch.

	.EXAMPLE
		GitSwitch
		Switches to master or main (whichever exists).

	.EXAMPLE
		GitSwitch -BranchName "feature/my-feature"
		Switches to "feature/my-feature" if it exists.
	#>
	param(
		[string]$BranchName
	)

	if (-not $BranchName) {
		if (BranchExists "master") { git switch master }
		elseif (BranchExists "main") { git switch main }
		else { Write-LogError "Neither 'master' nor 'main' branch exists in this repository!" }
	}
	else {
		if (BranchExists $BranchName) { git switch $BranchName }
		else { Write-LogError "Branch '$BranchName' does not exist!" }
	}
}
