function GitBranchDeleteAndPrune {
	<#
	.SYNOPSIS
		Force-deletes local branches and prunes stale remote-tracking refs for origin.

	.DESCRIPTION
		Runs `git branch -D <BranchName>` to force-delete the specified local branch,
		then runs `git remote prune origin` to remove any remote-tracking refs that no
		longer exist on the remote.
		Without -BranchName, the local branches (the checked-out one left out) are
		offered through Resolve-Selection, which takes one or more; pressing Enter
		deletes nothing. Each selected branch is deleted on its own and origin is
		pruned once, only when at least one branch was deleted.
		Alias: gbd

	.PARAMETER BranchName
		Name of the local branch to delete. Omit it to pick branches from a menu.

	.EXAMPLE
		GitBranchDeleteAndPrune -BranchName "feature/done"
		Deletes the local "feature/done" branch and prunes stale origin refs.

	.EXAMPLE
		gbd
		Lists the local branches and deletes the ones selected; Enter deletes none.
	#>
	param( [string] $BranchName )

	if ($BranchName) {
		$branches = @($BranchName)
	}
	else {
		# Full refs, so a tag of the same name never makes a short name ambiguous.
		$refs = @(git for-each-ref --format='%(refname)' refs/heads/)
		if ($LASTEXITCODE -ne 0) {
			return
		}
		$current = git symbolic-ref -q HEAD 2>$null
		$options = @($refs | Where-Object { $_ -and $_ -ne $current } | ForEach-Object { $_ -replace '^refs/heads/', '' })

		if ($options.Count -eq 0) {
			Write-Host -ForegroundColor Yellow "`n=> No local branch to delete besides the checked-out one"
			return
		}

		$branches = @(Resolve-Selection -OptionList $options -MenuTitle "[Local Branches]" `
				-PromptMessage "Enter branch(es) to delete by number or name, or press [Enter] to delete none" `
				-AllowEmptyPromptResponse -AllowMultipleSelections | Where-Object { $_ })
		if ($branches.Count -eq 0) {
			return
		}
		# Keeps the answer apart from git's output below it.
		Write-Host ""
	}

	$deleted = 0
	foreach ($branch in $branches) {
		git branch -D $branch
		if ($LASTEXITCODE -eq 0) {
			$deleted++
		}
	}
	if ($deleted -gt 0) {
		git remote prune origin
	}
}
