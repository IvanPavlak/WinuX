function Restore-RepositoryStash {
	<#
	.SYNOPSIS
		Gives back exactly one stash, identified by its commit, and drops it only once it is
		fully restored.

	.DESCRIPTION
		The safe counterpart of `git stash pop` for Update-Repository. `git stash pop` takes
		whatever sits on top of the stash list, which is only the stash just made if nothing else
		stashed in between and the push really created one. Neither is guaranteed: a dirty status
		that git cannot stash (a submodule with new commits, line-ending noise) makes
		`git stash push` print "No local changes to save" and exit 0 without creating anything,
		and another process can stash at any time. A blind pop would then apply the user's own,
		unrelated older stash to the working tree.

		This function never touches any stash but the one whose commit it is given:

		1. The commit is looked up in the stash list. Not there: "Missing", nothing is done.
		2. `git stash apply --index <commit>` restores the changes AND what was staged. Git
		   refuses that, changing nothing, when the staged changes no longer apply to the
		   index; then a plain `git stash apply <commit>` restores the changes, unstaged.
		3. Only after a clean apply is that one entry dropped, looked up again by its commit.
		   An apply that conflicts keeps the stash, so nothing can be lost: the working tree
		   holds the conflict markers and the stash still holds the original changes.

		Runs inside the repository (the caller holds Push-Location). With -Quiet git is
		silenced; otherwise git's own output reaches the console.

	.PARAMETER StashCommit
		The full commit id of the stash to restore (`git rev-parse refs/stash` right after the
		push that created it).

	.PARAMETER Quiet
		Silence git.

	.OUTPUTS
		[string] - Restored (applied and dropped), Conflict (applied with conflicts, or not
		applied; the stash is kept), or Missing (no such stash; nothing was done).

	.EXAMPLE
		$stash = git rev-parse refs/stash
		Restore-RepositoryStash -StashCommit $stash
		Restores that stash and drops it, or keeps it when the restore conflicts.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$StashCommit,

		[Parameter(Mandatory = $false)]
		[switch]$Quiet
	)

	if (@(git stash list --format=%H) -notcontains $StashCommit) { return "Missing" }

	$quietFlag = @(if ($Quiet) { "--quiet" })
	$applyWithIndex = @("stash", "apply", "--index") + $quietFlag + @($StashCommit)
	if ($Quiet) { git @applyWithIndex 2>$null | Out-Null } else { git @applyWithIndex | Out-Host }
	$applied = ($LASTEXITCODE -eq 0)

	if (-not $applied) {
		# --index refuses without touching anything when the staged part cannot be rebuilt; a
		# clean working tree afterwards is the proof. Only then is a plain apply safe to try.
		# A dirty tree means the apply did start and conflicted - leave it, the stash is kept.
		if (-not (git status --porcelain)) {
			$applyPlain = @("stash", "apply") + $quietFlag + @($StashCommit)
			if ($Quiet) { git @applyPlain 2>$null | Out-Null } else { git @applyPlain | Out-Host }
			$applied = ($LASTEXITCODE -eq 0)
		}
	}

	if (-not $applied) { return "Conflict" }

	# Drop exactly this entry. Its position can have moved since the lookup above, so it is
	# looked up again; if it cannot be found the stash simply stays - a harmless duplicate.
	$position = [array]::IndexOf(@(git stash list --format=%H), $StashCommit)
	if ($position -ge 0) {
		if ($Quiet) { git stash drop --quiet "stash@{$position}" 2>$null | Out-Null } else { git stash drop "stash@{$position}" | Out-Host }
	}
	return "Restored"
}
