function Git-Diff {
	<#
	.SYNOPSIS
		Shows the diff between the working tree and the last commit.

	.DESCRIPTION
		Runs `git diff HEAD` to display all unstaged and staged changes relative to HEAD.
		Alias: gdf

	.EXAMPLE
		Git-Diff
		Outputs the full diff against the current HEAD commit.
	#>
	& git diff HEAD
}
