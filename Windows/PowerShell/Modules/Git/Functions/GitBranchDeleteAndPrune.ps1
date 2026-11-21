function GitBranchDeleteAndPrune {
	<#
	.SYNOPSIS
		Deletes local branches and prunes stale remote-tracking refs for origin.

	.DESCRIPTION
		Runs `git branch -d <BranchName>` on each named branch, then `git remote prune origin`
		to remove any remote-tracking refs that no longer exist on the remote.
		`git branch -d` refuses a branch that is not fully merged into its upstream or HEAD, a
		squash-merged branch included. The refused branches are named and offered once for a
		force delete (`git branch -D`); Enter keeps them. -Force deletes with `-D` straight away
		and asks nothing.
		Without -BranchName, the local branches (the checked-out one left out) are offered
		through Resolve-Selection, which takes one or more; pressing Enter deletes nothing.
		Each branch is deleted on its own and origin is pruned once, only when at least one
		branch was deleted.
		Alias: gbd

	.PARAMETER BranchName
		Name(s) of the local branch(es) to delete. Omit it to pick branches from a menu.

	.PARAMETER Force
		Deletes with `git branch -D`, unmerged branches included, without asking.

	.EXAMPLE
		GitBranchDeleteAndPrune -BranchName "feature/done"
		Deletes the local "feature/done" branch if it is merged, offers to force it if not, and
		prunes stale origin refs.

	.EXAMPLE
		gbd feature/a, feature/b -Force
		Force-deletes both branches and prunes stale origin refs once.

	.EXAMPLE
		gbd
		Lists the local branches and deletes the ones selected; Enter deletes none.
	#>
	param(
		[Parameter(Position = 0)]
		[string[]] $BranchName,

		[switch] $Force
	)

	if ($BranchName) {
		$branches = @($BranchName | Where-Object { $_ })
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

	$deleteFlag = if ($Force) { "-D" } else { "-d" }
	$deleted = 0
	$refused = @()
	foreach ($branch in $branches) {
		git branch $deleteFlag $branch
		if ($LASTEXITCODE -eq 0) {
			$deleted++
		}
		else {
			$refused += $branch
		}
	}

	# Only a plain delete asks: -Force already used -D, and a branch -D refuses (missing, checked
	# out in a worktree) would only fail again.
	if (-not $Force -and $refused.Count -gt 0) {
		Write-Host -ForegroundColor Yellow "`n=> Not deleted: $($refused -join ', ') (not fully merged, or see git's message above)"
		$answer = Resolve-Selection -ConfirmationMessage "Force-delete $($refused -join ', ') with git branch -D?" -HideMenuTitle
		if ($answer -eq "Yes") {
			Write-Host ""
			foreach ($branch in $refused) {
				git branch -D $branch
				if ($LASTEXITCODE -eq 0) {
					$deleted++
				}
			}
		}
	}

	if ($deleted -gt 0) {
		git remote prune origin
	}
}
